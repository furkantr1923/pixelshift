import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

import '../ai/ai_models.dart';
import '../ai/ai_service.dart';
import '../ai/command_parser.dart';
import '../app/services.dart';
import '../core/errors.dart';
import '../core/ids.dart';
import '../filters/adjustments.dart';
import '../image_engine/classic.dart';
import '../image_engine/codec.dart';
import '../image_engine/engine.dart';
import '../image_engine/geometry.dart';
import '../image_engine/ops.dart';
import '../image_engine/raster.dart';
import '../layers/layer.dart';
import '../layers/layer_painter.dart';
import '../platform_services/ui_images.dart';
import '../projects/project_database.dart';
import 'document.dart';
import 'history.dart';

enum EditorTool {
  select('Seç / Taşı'),
  crop('Kırp ve döndür'),
  adjust('Ayarlar'),
  filters('Filtreler'),
  text('Metin'),
  shapes('Şekiller'),
  stickers('Çıkartmalar'),
  mask('Maske'),
  ai('AI araçları'),
  layers('Katmanlar'),
  inpaint('Nesne silme fırçası');

  const EditorTool(this.label);
  final String label;
}

/// Kırpma oranı ön ayarı (null = serbest).
class CropAspect {
  const CropAspect(this.label, this.ratio, {this.original = false});
  final String label;
  final double? ratio;
  final bool original;

  static const presets = [
    CropAspect('Serbest', null),
    CropAspect('Orijinal', null, original: true),
    CropAspect('1:1', 1),
    CropAspect('4:5', 4 / 5),
    CropAspect('3:4', 3 / 4),
    CropAspect('4:3', 4 / 3),
    CropAspect('3:2', 3 / 2),
    CropAspect('2:3', 2 / 3),
    CropAspect('16:9', 16 / 9),
    CropAspect('9:16', 9 / 16),
  ];
}

/// Düzenleyicinin tüm durumunu ve işlemlerini yöneten denetleyici.
class EditorController extends ChangeNotifier {
  EditorController._(this.services, this._info, this._history) : _doc = _history.current;

  final AppServices services;
  ProjectInfo _info;
  final History<EditDocument> _history;
  EditDocument _doc;

  int _revision = 0;
  int _savedRevision = 0;
  bool _disposed = false;

  // Önizleme durumu
  Raster? _sourcePreview;
  String? _loadedSource;
  ui.Image? baseImage;
  ui.Image? cropImage;
  bool rendering = false;
  int _renderSeq = 0;
  Timer? _renderTimer;
  Object? _lastRenderKey;
  Object? _lastCropKey;

  // Katman görselleri (önizleme boyutu)
  final LayerImages layerImages = {};
  final Set<String> _loadingAssets = {};

  // Araç durumu
  EditorTool _tool = EditorTool.select;
  String? _selectedLayerId;
  NormRect? cropDraft;
  CropAspect cropAspect = CropAspect.presets.first;
  final List<List<double>> inpaintStrokes = [];
  double inpaintBrush = 40; // belge pikseli
  double maskBrush = 40;
  double maskFeather = 0.5;
  bool maskHide = true;
  bool showMaskOverlay = false;

  /// Uzun süren işlem (kullanıcıya gösterilir).
  String? busyMessage;

  /// Arayüz mesajları (SnackBar).
  void Function(String message, {bool error})? onMessage;

  // ------------------------------------------------------------ Açma

  static Future<EditorController> open(AppServices services, String projectId) async {
    final data = await services.store.load(projectId);
    final history = History<EditDocument>(data.history.first);
    history.restore(data.history, data.labels, data.index);
    final c = EditorController._(services, data.info, history);
    await c._ensureSource();
    c._ensureLayerImages();
    c._scheduleRender(immediate: true);
    return c;
  }

  ProjectInfo get info => _info;
  EditDocument get doc => _doc;
  History<EditDocument> get history => _history;
  bool get isDirty => _revision != _savedRevision;
  bool get canUndo => _history.canUndo && _tool != EditorTool.crop;
  bool get canRedo => _history.canRedo && _tool != EditorTool.crop;
  EditorTool get tool => _tool;
  String? get selectedLayerId => _selectedLayerId;
  Layer? get selectedLayer => _doc.layerById(_selectedLayerId);
  Raster? get sourcePreview => _sourcePreview;

  /// Ekranda gösterilen belge boyutu (kırpma modunda kırpılmamış boyut).
  Size get displaySize {
    if (_tool == EditorTool.crop) {
      final (w, h) = _doc.geometry.withoutCrop().outputSize(_doc.sourceWidth, _doc.sourceHeight);
      return Size(w.toDouble(), h.toDouble());
    }
    return Size(_doc.canvasWidth.toDouble(), _doc.canvasHeight.toDouble());
  }

  List<double> get colorMatrix => _doc.adjustments.colorMatrix().values;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  void _message(String m, {bool error = false}) => onMessage?.call(m, error: error);

  // ------------------------------------------------------------ Belge değişiklikleri

  /// Geçmişe eklemeden canlı önizleme (ör. kaydırıcı sürüklenirken).
  void preview(EditDocument d) {
    _doc = d;
    _scheduleRender();
    _notify();
  }

  /// Değişikliği geçmişe ekler.
  void commit(String label, [EditDocument? d]) {
    if (d != null) _doc = d;
    if (identical(_doc, _history.current)) return;
    _history.push(_doc, label);
    _revision++;
    _scheduleRender();
    _notify();
  }

  void undo() {
    if (!canUndo) return;
    _doc = _history.undo();
    _afterHistoryJump();
  }

  void redo() {
    if (!canRedo) return;
    _doc = _history.redo();
    _afterHistoryJump();
  }

  void jumpTo(int index) {
    if (index == _history.index) return;
    while (_history.index > index && _history.canUndo) {
      _history.undo();
    }
    while (_history.index < index && _history.canRedo) {
      _history.redo();
    }
    _doc = _history.current;
    _afterHistoryJump();
  }

  void _afterHistoryJump() {
    _revision++;
    if (_doc.layerById(_selectedLayerId) == null) _selectedLayerId = null;
    unawaited(_ensureSource().then((_) => _scheduleRender(immediate: true)));
    _ensureLayerImages();
    _notify();
  }

  // ------------------------------------------------------------ Kaynak ve önizleme

  Future<void> _ensureSource() async {
    final file = _doc.sourceFile;
    if (_loadedSource == file && _sourcePreview != null) return;
    final bytes = await services.store.readFile(_info.id, file);
    final load = await ImageEngine.loadPreview(bytes, file, services.settings.previewMaxSide);
    _sourcePreview = load.preview;
    _loadedSource = file;
    _lastRenderKey = null;
    _lastCropKey = null;
  }

  Object _detailKey(Adjustments a) =>
      Object.hash(a.shadows, a.highlights, a.sharpness, a.clarity, a.blur, a.effectiveVignette, a.effectiveGrain);

  void _scheduleRender({bool immediate = false}) {
    _renderTimer?.cancel();
    if (immediate) {
      unawaited(_render());
    } else {
      _renderTimer = Timer(const Duration(milliseconds: 35), () => unawaited(_render()));
    }
  }

  Future<void> _render() async {
    final src = _sourcePreview;
    if (src == null || _disposed) return;
    if (_loadedSource != _doc.sourceFile) {
      await _ensureSource();
      if (_disposed) return;
    }
    final source = _sourcePreview!;
    final adj = _doc.adjustments;
    final inCrop = _tool == EditorTool.crop;
    final geometry = _doc.geometry;
    final key = Object.hash(_loadedSource, geometry, _detailKey(adj));
    final cropKey = Object.hash(_loadedSource, geometry.withoutCrop(), _detailKey(adj));
    final needBase = key != _lastRenderKey;
    final needCrop = inCrop && cropKey != _lastCropKey;
    if (!needBase && !needCrop) return;

    final seq = ++_renderSeq;
    rendering = true;
    _notify();
    try {
      if (needCrop) {
        final r = await ImageEngine.renderPreview(source, geometry.withoutCrop(), adj);
        if (seq != _renderSeq || _disposed) return;
        final img = await UiImages.fromRaster(r);
        if (seq != _renderSeq || _disposed) {
          img.dispose();
          return;
        }
        cropImage?.dispose();
        cropImage = img;
        _lastCropKey = cropKey;
      }
      if (needBase) {
        final r = await ImageEngine.renderPreview(source, geometry, adj);
        if (seq != _renderSeq || _disposed) return;
        final img = await UiImages.fromRaster(r);
        if (seq != _renderSeq || _disposed) {
          img.dispose();
          return;
        }
        baseImage?.dispose();
        baseImage = img;
        _lastRenderKey = key;
      }
    } catch (e) {
      _message('Önizleme oluşturulamadı: ${describeError(e)}', error: true);
    } finally {
      if (seq == _renderSeq) {
        rendering = false;
        _notify();
      }
    }
  }

  void _ensureLayerImages() {
    for (final l in _doc.layers) {
      if (l is ImageLayer && !layerImages.containsKey(l.assetFile) && !_loadingAssets.contains(l.assetFile)) {
        unawaited(_loadAsset(l.assetFile));
      }
    }
  }

  Future<void> _loadAsset(String asset) async {
    _loadingAssets.add(asset);
    try {
      final bytes = await services.store.readAsset(_info.id, asset);
      final load = await ImageEngine.loadPreview(bytes, asset, 1600);
      final img = await UiImages.fromRaster(load.preview);
      if (_disposed) {
        img.dispose();
        return;
      }
      layerImages[asset] = img;
      _notify();
    } catch (e) {
      _message('Katman görseli yüklenemedi: ${describeError(e)}', error: true);
    } finally {
      _loadingAssets.remove(asset);
    }
  }

  // ------------------------------------------------------------ Araçlar

  void setTool(EditorTool t) {
    if (_tool == t) return;
    if (_tool == EditorTool.crop && t != EditorTool.crop) cancelCrop(notify: false);
    if (_tool == EditorTool.inpaint && t != EditorTool.inpaint) inpaintStrokes.clear();
    _tool = t;
    if (t == EditorTool.crop) {
      cropDraft = _doc.geometry.crop;
      _scheduleRender(immediate: true);
    }
    if (t == EditorTool.mask && selectedLayer == null && _doc.layers.isNotEmpty) {
      _selectedLayerId = _doc.layers.last.id;
    }
    _notify();
  }

  void selectLayer(String? id) {
    _selectedLayerId = id;
    _notify();
  }

  // ------------------------------------------------------------ Kırpma / döndürme

  (int, int) get _uncroppedSize => _doc.geometry.withoutCrop().outputSize(_doc.sourceWidth, _doc.sourceHeight);

  void setCropDraft(NormRect r) {
    cropDraft = r.clampValid();
    _notify();
  }

  void setCropAspect(CropAspect a) {
    cropAspect = a;
    final ratio = cropAspectRatio;
    if (ratio != null) {
      final (w, h) = _uncroppedSize;
      // Mevcut taslağın merkezinde, sığabilecek en büyük dikdörtgen.
      final cur = cropDraft ?? NormRect.full;
      final cx = (cur.left + cur.right) / 2, cy = (cur.top + cur.bottom) / 2;
      var nw = 1.0, nh = (w / ratio) / h;
      if (nh > 1) {
        nh = 1;
        nw = (h * ratio) / w;
      }
      final scale = math.min(1.0, math.max(cur.width / nw, cur.height / nh));
      nw *= scale;
      nh *= scale;
      var l = cx - nw / 2, t = cy - nh / 2;
      l = l.clamp(0.0, 1 - nw).toDouble();
      t = t.clamp(0.0, 1 - nh).toDouble();
      cropDraft = NormRect(l, t, l + nw, t + nh);
    }
    _notify();
  }

  /// Piksel cinsinden genişlik/yükseklik oranı (null = serbest).
  double? get cropAspectRatio {
    if (cropAspect.original) {
      final (w, h) = _uncroppedSize;
      return w / h;
    }
    return cropAspect.ratio;
  }

  void rotate90({bool clockwise = true}) {
    final g = _doc.geometry;
    // Kırpma dikdörtgeni görüntüyle birlikte döner.
    NormRect rot(NormRect c) => clockwise
        ? NormRect(1 - c.bottom, c.left, 1 - c.top, c.right)
        : NormRect(c.top, 1 - c.right, c.bottom, 1 - c.left);
    if (cropDraft != null) cropDraft = rot(cropDraft!);
    // Tek eksende çevrilmiş görüntüde görsel saat yönü, ham döndürmenin tersidir.
    var delta = clockwise ? 1 : 3;
    if (g.flipH != g.flipV) delta = 4 - delta;
    final ng = g.copyWith(quarterTurns: g.quarterTurns + delta, crop: rot(g.crop));
    commit(clockwise ? 'Sağa döndür' : 'Sola döndür', _doc.copyWith(geometry: ng));
  }

  void flip({required bool horizontal}) {
    final g = _doc.geometry;
    NormRect fl(NormRect c) =>
        horizontal ? NormRect(1 - c.right, c.top, 1 - c.left, c.bottom) : NormRect(c.left, 1 - c.bottom, c.right, 1 - c.top);
    if (cropDraft != null) cropDraft = fl(cropDraft!);
    // Çevirme düzleştirme açısının yönünü de aynalar.
    final ng = (horizontal ? g.copyWith(flipH: !g.flipH) : g.copyWith(flipV: !g.flipV))
        .copyWith(crop: fl(g.crop), straighten: -g.straighten);
    commit(horizontal ? 'Yatay çevir' : 'Dikey çevir', _doc.copyWith(geometry: ng));
  }

  void previewStraighten(double degrees) => preview(_doc.copyWith(geometry: _doc.geometry.copyWith(straighten: degrees)));

  void commitStraighten() => commit('Düzleştir');

  void applyCrop() {
    final draft = cropDraft;
    _tool = EditorTool.select;
    if (draft != null && draft != _doc.geometry.crop) {
      commit('Kırpma', _doc.copyWith(geometry: _doc.geometry.copyWith(crop: draft)));
    } else {
      _scheduleRender(immediate: true);
      _notify();
    }
    cropDraft = null;
  }

  void cancelCrop({bool notify = true}) {
    cropDraft = null;
    if (_tool == EditorTool.crop) _tool = EditorTool.select;
    _scheduleRender(immediate: true);
    if (notify) _notify();
  }

  void resetGeometry() {
    cropDraft = NormRect.full;
    commit('Geometriyi sıfırla', _doc.copyWith(geometry: Geometry.identity));
  }

  // ------------------------------------------------------------ Ayarlar

  void previewAdjustments(Adjustments a) => preview(_doc.copyWith(adjustments: a));

  void commitAdjustments(String label, [Adjustments? a]) => commit(label, a == null ? null : _doc.copyWith(adjustments: a));

  void resetAdjustments() => commit('Ayarları sıfırla', _doc.copyWith(adjustments: Adjustments.none));

  Future<void> autoAdjust() async {
    final src = _sourcePreview;
    if (src == null) return;
    await _busy('Otomatik ayar hesaplanıyor…', () async {
      final current = _doc.adjustments;
      final geometry = _doc.geometry;
      final suggested = await _suggestInIsolate(src, geometry, current);
      commit('Otomatik ayar', _doc.copyWith(adjustments: suggested));
    });
  }

  static Future<Adjustments> _suggestInIsolate(Raster src, Geometry g, Adjustments current) =>
      Isolate.run(() => Classic.suggestAdjustments(Ops.applyGeometry(src, g), current));

  /// Yerel Türkçe komut yorumlayıcısı.
  CommandResult applyCommand(String text) {
    final result = CommandParser.parse(text, _doc.adjustments, _doc.geometry);
    if (!result.isEmpty) {
      commit('Komut: ${text.trim()}', _doc.copyWith(adjustments: result.adjustments, geometry: result.geometry));
    }
    return result;
  }

  // ------------------------------------------------------------ Katmanlar

  Offset get canvasCenter => Offset(_doc.canvasWidth / 2, _doc.canvasHeight / 2);
  double get _unit => math.max(_doc.canvasWidth, _doc.canvasHeight).toDouble();

  void addLayer(Layer layer, String label) {
    commit(label, _doc.addLayer(layer));
    _selectedLayerId = layer.id;
    if (_tool == EditorTool.inpaint || _tool == EditorTool.crop) _tool = EditorTool.select;
    _ensureLayerImages();
    _notify();
  }

  void addText({String text = 'Metninizi yazın', double sizeFactor = 0.07, bool bold = true, String font = 'Inter'}) {
    final c = canvasCenter;
    addLayer(
      TextLayer(
        id: newId('l'),
        name: 'Metin',
        cx: c.dx,
        cy: c.dy,
        text: text,
        fontFamily: font,
        fontSize: (_unit * sizeFactor).roundToDouble(),
        bold: bold,
        shadow: true,
      ),
      'Metin ekle',
    );
  }

  void addSticker(String emoji) {
    final c = canvasCenter;
    addLayer(
      TextLayer(
        id: newId('l'),
        name: 'Çıkartma $emoji',
        cx: c.dx,
        cy: c.dy,
        text: emoji,
        fontSize: (_unit * 0.16).roundToDouble(),
        isSticker: true,
        lineHeight: 1.1,
      ),
      'Çıkartma ekle',
    );
  }

  void addShape(ShapeKind kind) {
    final c = canvasCenter;
    final s = _unit * 0.25;
    final h = switch (kind) {
      ShapeKind.line => s * 0.04,
      ShapeKind.arrow => s * 0.5,
      ShapeKind.rect || ShapeKind.roundRect => s * 0.62,
      _ => s,
    };
    addLayer(
      ShapeLayer(
        id: newId('l'),
        name: kind.label,
        cx: c.dx,
        cy: c.dy,
        shape: kind,
        width: s,
        height: h,
        fill: kind == ShapeKind.bubble ? 0xFFFFFFFF : 0xFF7C5CFF,
        cornerRadius: s * 0.12,
      ),
      '${kind.label} ekle',
    );
  }

  /// Görseli katman olarak ekler (kolaj, logo, ikinci fotoğraf...).
  Future<void> addImageLayer(Uint8List bytes, String fileName, {Rect? box}) async {
    await _busy('Görsel katman ekleniyor…', () async {
      final imported = await ImageEngine.importImage(bytes, fileName, 1600);
      final asset = await services.store.addAsset(_info.id, imported.storedBytes, imported.storedExtension);
      final img = await UiImages.fromRaster(imported.preview);
      layerImages[asset] = img;
      double w, h;
      Offset c;
      if (box != null) {
        w = box.width;
        h = box.height;
        c = box.center;
      } else {
        final maxSide = _unit * 0.45;
        final s = maxSide / math.max(imported.width, imported.height);
        w = imported.width * s;
        h = imported.height * s;
        c = canvasCenter;
      }
      addLayer(
        ImageLayer(
          id: newId('l'),
          name: fileName.length > 28 ? '${fileName.substring(0, 25)}…' : fileName,
          cx: c.dx,
          cy: c.dy,
          assetFile: asset,
          assetWidth: imported.width,
          assetHeight: imported.height,
          width: w,
          height: h,
        ),
        'Görsel katman ekle',
      );
      if (imported.note != null) _message(imported.note!);
    });
  }

  void previewLayer(Layer layer) => preview(_doc.replaceLayer(layer));

  void updateLayer(Layer layer, String label) => commit(label, _doc.replaceLayer(layer));

  void deleteLayer(String id) {
    if (_selectedLayerId == id) _selectedLayerId = null;
    commit('Katmanı sil', _doc.removeLayer(id));
  }

  void duplicateLayer(String id) {
    final l = _doc.layerById(id);
    if (l == null) return;
    final j = l.toJson()
      ..['id'] = newId('l')
      ..['name'] = '${l.name} kopya'
      ..['cx'] = l.cx + _unit * 0.03
      ..['cy'] = l.cy + _unit * 0.03;
    final copy = Layer.fromJson(j);
    final list = [..._doc.layers];
    list.insert(list.indexWhere((x) => x.id == id) + 1, copy);
    commit('Katmanı çoğalt', _doc.copyWith(layers: list));
    _selectedLayerId = copy.id;
    _notify();
  }

  void moveLayer(String id, int delta) => commit(delta > 0 ? 'Katmanı yukarı taşı' : 'Katmanı aşağı taşı', _doc.moveLayer(id, delta));

  void reorderLayers(int oldIndex, int newIndex) => commit('Katman sırası', _doc.reorderLayer(oldIndex, newIndex));

  void toggleVisibility(String id) {
    final l = _doc.layerById(id);
    if (l == null) return;
    commit(l.visible ? 'Katmanı gizle' : 'Katmanı göster', _doc.replaceLayer(l.copyBase(visible: !l.visible)));
  }

  void toggleLock(String id) {
    final l = _doc.layerById(id);
    if (l == null) return;
    commit(l.locked ? 'Kilidi aç' : 'Kilitle', _doc.replaceLayer(l.copyBase(locked: !l.locked)));
  }

  void renameLayer(String id, String name) {
    final l = _doc.layerById(id);
    if (l == null || name.trim().isEmpty) return;
    commit('Katmanı yeniden adlandır', _doc.replaceLayer(l.copyBase(name: name.trim())));
  }

  /// Katmanı tuvalin ortasına hizalar.
  void centerLayer(String id) {
    final l = _doc.layerById(id);
    if (l == null) return;
    final c = canvasCenter;
    commit('Ortala', _doc.replaceLayer(l.copyBase(cx: c.dx, cy: c.dy)));
  }

  // ------------------------------------------------------------ Maske

  /// Fırça darbesine nokta ekler (belge koordinatı → katman yereli).
  void maskStrokeStart(Offset docPoint) {
    final l = selectedLayer;
    if (l == null) {
      _message('Maske için önce bir katman seçin.');
      return;
    }
    final p = LayerPainter.toLocal(l, docPoint);
    final stroke = MaskStroke(points: [p.dx, p.dy], radius: maskBrush / l.scale, feather: maskFeather, hide: maskHide);
    preview(_doc.replaceLayer(l.copyBase(mask: [...l.mask, stroke], maskEnabled: true)));
  }

  void maskStrokeUpdate(Offset docPoint) {
    final l = selectedLayer;
    if (l == null || l.mask.isEmpty) return;
    final p = LayerPainter.toLocal(l, docPoint);
    final last = l.mask.last;
    final n = last.points.length;
    if (n >= 2) {
      final dx = last.points[n - 2] - p.dx, dy = last.points[n - 1] - p.dy;
      if (dx * dx + dy * dy < math.pow(last.radius * 0.15, 2)) return;
    }
    final strokes = [...l.mask]..[l.mask.length - 1] = last.withPoint(p.dx, p.dy);
    preview(_doc.replaceLayer(l.copyBase(mask: strokes)));
  }

  void maskStrokeEnd() => commit(maskHide ? 'Maske fırçası' : 'Maske silgisi');

  void clearMask() {
    final l = selectedLayer;
    if (l == null || l.mask.isEmpty) return;
    commit('Maskeyi temizle', _doc.replaceLayer(l.copyBase(mask: const [])));
  }

  void setMaskEnabled(bool enabled) {
    final l = selectedLayer;
    if (l == null) return;
    commit(enabled ? 'Maskeyi etkinleştir' : 'Maskeyi devre dışı bırak', _doc.replaceLayer(l.copyBase(maskEnabled: enabled)));
  }

  void setMaskSettings({double? brush, double? feather, bool? hide, bool? overlay}) {
    if (brush != null) maskBrush = brush;
    if (feather != null) maskFeather = feather;
    if (hide != null) maskHide = hide;
    if (overlay != null) showMaskOverlay = overlay;
    _notify();
  }

  // ------------------------------------------------------------ Nesne silme fırçası

  void inpaintStrokeStart(Offset p) {
    inpaintStrokes.add([inpaintBrush, p.dx, p.dy]);
    _notify();
  }

  void inpaintStrokeUpdate(Offset p) {
    if (inpaintStrokes.isEmpty) return;
    final s = inpaintStrokes.last;
    final dx = s[s.length - 2] - p.dx, dy = s[s.length - 1] - p.dy;
    if (dx * dx + dy * dy < math.pow(inpaintBrush * 0.2, 2)) return;
    s.addAll([p.dx, p.dy]);
    _notify();
  }

  void setInpaintBrush(double v) {
    inpaintBrush = v;
    _notify();
  }

  void clearInpaint() {
    inpaintStrokes.clear();
    _notify();
  }

  void undoInpaintStroke() {
    if (inpaintStrokes.isNotEmpty) inpaintStrokes.removeLast();
    _notify();
  }

  // ------------------------------------------------------------ AI / piksel işlemleri

  /// Katmanlar hariç, tüm ayarları uygulanmış tam çözünürlüklü taban.
  Future<Raster> renderFlattenedBase() async {
    final bytes = await services.store.readFile(_info.id, _doc.sourceFile);
    return ImageEngine.renderFull(bytes, _doc.sourceFile, _doc.geometry, _doc.adjustments);
  }

  /// AI veya klasik işlem sonucunu yeni kaynak sürümü olarak uygular (geri alınabilir).
  Future<void> applyPixelResult(Raster result, String label) async {
    final png = await ImageEngine.encode(result, ExportFormat.png, 100);
    final file = await services.store.addSourceVersion(_info.id, png, 'png');
    final oldW = _doc.canvasWidth, oldH = _doc.canvasHeight;
    final sx = result.width / oldW, sy = result.height / oldH;
    var layers = _doc.layers;
    if ((sx - 1).abs() > 0.001 || (sy - 1).abs() > 0.001) {
      layers = [for (final l in layers) l.copyBase(cx: l.cx * sx, cy: l.cy * sy, scale: l.scale * (sx + sy) / 2)];
    }
    final preview = await ImageEngine.thumbnail(result, services.settings.previewMaxSide);
    _sourcePreview = preview;
    _loadedSource = file;
    _lastRenderKey = null;
    commit(
      label,
      EditDocument(sourceFile: file, sourceWidth: result.width, sourceHeight: result.height, layers: layers),
    );
    _scheduleRender(immediate: true);
  }

  Future<AiResult?> runAi(AiService service, AiProvider provider, AiTask task,
      {Map<String, Object?> params = const {}, required ProgressCallback progress, required CancelToken cancel}) async {
    final base = await renderFlattenedBase();
    Uint8List? mask;
    if (task == AiTask.objectRemoval) {
      if (inpaintStrokes.isEmpty) throw const UserFacingException('Silinecek alanı fırçayla boyayın.');
      mask = await _rasterizeInIsolate(base.width, base.height, [for (final s in inpaintStrokes) List<double>.of(s)]);
    }
    final result = await service.run(
      provider,
      AiRequest(task: task, image: base, mask: mask, params: params),
      progress: progress,
      cancel: cancel,
    );
    progress('Sonuç projeye ekleniyor…', null);
    await applyPixelResult(result.image, task.label);
    if (task == AiTask.objectRemoval) inpaintStrokes.clear();
    return result;
  }

  static Future<Uint8List> _rasterizeInIsolate(int w, int h, List<List<double>> strokes) =>
      Isolate.run(() => Classic.rasterizeStrokes(w, h, strokes));

  // ------------------------------------------------------------ Kaydetme

  Future<void> save() async {
    await _busy('Proje kaydediliyor…', () async {
      Uint8List? thumb;
      try {
        thumb = await renderThumbnailPng(360);
      } catch (_) {
        thumb = null;
      }
      await services.store.save(_info, _history.items, _history.labels, _history.index, thumbPng: thumb);
      _info = (await services.database.byId(_info.id)) ?? _info;
      _savedRevision = _revision;
    });
    _message('Proje kaydedildi.');
  }

  Future<void> rename(String name) async {
    _info = await services.store.rename(_info, name);
    _notify();
  }

  /// Önizleme bileşimini (renk + katmanlar) küçük PNG olarak üretir.
  Future<Uint8List> renderThumbnailPng(int maxSide) async {
    final base = baseImage;
    final w = _doc.canvasWidth.toDouble(), h = _doc.canvasHeight.toDouble();
    final scale = maxSide / math.max(w, h);
    final tw = math.max(1, (w * scale).round()), th = math.max(1, (h * scale).round());
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    canvas.scale(scale);
    if (base != null) {
      canvas.drawImageRect(
        base,
        Rect.fromLTWH(0, 0, base.width.toDouble(), base.height.toDouble()),
        Rect.fromLTWH(0, 0, w, h),
        Paint()
          ..filterQuality = FilterQuality.medium
          ..colorFilter = ColorFilter.matrix(colorMatrix),
      );
    }
    LayerPainter.paintLayers(canvas, _doc.layers, layerImages);
    final picture = recorder.endRecording();
    final image = await picture.toImage(tw, th);
    picture.dispose();
    try {
      return await UiImages.toPng(image);
    } finally {
      image.dispose();
    }
  }

  Future<T?> _busy<T>(String message, Future<T> Function() action) async {
    busyMessage = message;
    _notify();
    try {
      return await action();
    } catch (e) {
      _message(describeError(e), error: true);
      return null;
    } finally {
      busyMessage = null;
      _notify();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _renderTimer?.cancel();
    baseImage?.dispose();
    cropImage?.dispose();
    for (final img in layerImages.values) {
      img.dispose();
    }
    layerImages.clear();
    super.dispose();
  }
}
