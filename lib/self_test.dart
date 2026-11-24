import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

import 'ai/ai_models.dart';
import 'ai/ai_service.dart';
import 'ai/command_parser.dart';
import 'ai/online_providers.dart';
import 'core/errors.dart';
import 'editor/document.dart';
import 'editor/history.dart';
import 'export/export_service.dart';
import 'filters/adjustments.dart';
import 'image_engine/classic.dart';
import 'image_engine/codec.dart';
import 'image_engine/engine.dart';
import 'image_engine/geometry.dart';
import 'image_engine/ops.dart';
import 'image_engine/raster.dart';
import 'image_engine/webp_encoder.dart';
import 'layers/layer.dart';
import 'projects/project_database.dart';
import 'projects/project_store.dart';

/// Derlenmiş (release) uygulamanın gerçek ortamda kendini sınaması.
///
/// `pixelshift.exe --self-test=<rapor>` ile çalışır. Görüntü motorunu,
/// kodlayıcıları, proje kayıt sistemini (gerçek SQLite + dosya sistemi),
/// GPU katman birleştirmesini ve gizlilik kurallarını gerçek ikili dosya
/// üzerinde doğrular. CI'da Windows sürümünün kanıtıdır.
Future<int> runSelfTest(String reportPath) async {
  final lines = <String>['PIXELSHIFT kendi kendini sınama raporu', 'Platform: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}', ''];
  var passed = true;
  void check(String name, bool ok, [String? info]) {
    lines.add('${ok ? '[GECTI]' : '[KALDI]'} $name${info != null ? ' ($info)' : ''}');
    if (!ok) passed = false;
  }

  Future<void> guard(String name, Future<void> Function() body) async {
    try {
      await body().timeout(const Duration(minutes: 3));
    } catch (e, st) {
      check('$name — beklenmeyen hata', false, '$e\n$st');
    }
  }

  Directory? temp;
  try {
    temp = await Directory.systemTemp.createTemp('pixelshift_selftest_');
    final src = syntheticImage(640, 480);

    await guard('Kodlayıcılar', () async {
      for (final f in ExportFormat.values) {
        final bytes = ImageEngine.encodeSync(src, f, f == ExportFormat.webp ? 100 : 92);
        final back = ImageCodec.decode(bytes, 'test.${f.extension}');
        final sameSize = back.width == src.width && back.height == src.height;
        final diff = meanAbsDiff(src, back, ignoreAlpha: !f.supportsTransparency);
        final exact = f == ExportFormat.png || f == ExportFormat.tiff || f == ExportFormat.webp;
        check('${f.label} kodla/çöz', sameSize && (exact ? diff == 0 : diff < 12),
            '${bytes.length} bayt, ort. fark ${diff.toStringAsFixed(2)}');
      }
      final lossy = ImageEngine.encodeSync(src, ExportFormat.webp, 75);
      final lossyBack = ImageCodec.decode(lossy, 'x.webp');
      check('WEBP kayıplı (VP8)', lossyBack.width == 640 && meanAbsDiff(src, lossyBack) < 20, '${lossy.length} bayt');
      final own = WebpEncoder.encode(src);
      check('PIXELSHIFT VP8L kodlayıcısı birebir', meanAbsDiff(src, ImageCodec.decode(own, 'y.webp')) == 0, '${own.length} bayt');
      check('Şeffaf PNG korunur', ImageCodec.decode(ImageEngine.encodeSync(src, ExportFormat.png, 90), 'a.png').hasTransparency);
      check('JPG şeffaflığı beyaza birleştirir', !ImageCodec.decode(ImageEngine.encodeSync(src, ExportFormat.jpg, 90), 'a.jpg').hasTransparency);
    });

    await guard('Hatalı dosyalar', () async {
      final png = ImageEngine.encodeSync(src, ExportFormat.png, 90);
      final corrupt = Uint8List.fromList(png.sublist(0, png.length ~/ 3));
      check('Bozuk PNG anlaşılır hata verir', _throwsUser(() => ImageCodec.decode(corrupt, 'bozuk.png')));
      check('Desteklenmeyen format reddedilir', _throwsUser(() => ImageCodec.decode(Uint8List.fromList('merhaba dünya'.codeUnits), 'not.txt')));
      check('Boş dosya reddedilir', _throwsUser(() => ImageCodec.decode(Uint8List(0), 'bos.jpg')));
    });

    await guard('Görüntü hattı', () async {
      final rotated = Ops.applyGeometry(src, const Geometry(quarterTurns: 1));
      check('90° döndürme boyutları', rotated.width == 480 && rotated.height == 640);
      final cropped = Ops.applyGeometry(src, const Geometry(crop: NormRect(0.25, 0.25, 0.75, 0.75)));
      check('Kırpma', cropped.width == 320 && cropped.height == 240);
      final straight = Ops.applyGeometry(src, const Geometry(straighten: 10));
      final (sw, sh) = Geometry.straightenedSize(640, 480, 10);
      check('Düzleştirme', straight.width == sw && straight.height == sh);
      final adj = const Adjustments(exposure: 30, contrast: 20, saturation: -100, sharpness: 50, vignette: -40);
      final out = ImageEngine.applyDetail(src, adj);
      adj.colorMatrix().applyTo(out);
      final i = (240 * 640 + 320) * 4;
      check('Doygunluk -100 gri üretir', out.rgba[i] == out.rgba[i + 1] && out.rgba[i + 1] == out.rgba[i + 2]);
      final small = Ops.resize(src, 160, 120);
      final big = Ops.resize(src, 1280, 960);
      check('Boyutlandırma (küçült/büyüt)', small.width == 160 && big.height == 960);
    });

    await guard('Büyük görsel', () async {
      final sw = Stopwatch()..start();
      final large = syntheticImage(6000, 4000);
      final jpg = ImageEngine.encodeSync(large, ExportFormat.jpg, 85);
      final (preview, fw, fh) = ImageCodec.decodePreview(jpg, 'buyuk.jpg', 2048);
      sw.stop();
      check('24 MP JPEG ölçekli önizleme', fw == 6000 && fh == 4000 && preview.longSide <= 2048,
          'önizleme ${preview.width}x${preview.height}, ${sw.elapsedMilliseconds} ms');
    });

    await guard('Klasik araçlar', () async {
      final mask = Classic.rasterizeStrokes(640, 480, [
        [20, 300, 200, 340, 220],
      ]);
      final inpainted = Classic.inpaint(src, mask);
      check('Nesne silme (inpainting)', inpainted.width == 640 && meanAbsDiff(src, inpainted) > 0);
      final studio = Raster.filled(300, 200, 245, 245, 245);
      for (var y = 60; y < 140; y++) {
        for (var x = 110; x < 190; x++) {
          final j = (y * 300 + x) * 4;
          studio.rgba[j] = 200;
          studio.rgba[j + 1] = 40;
          studio.rgba[j + 2] = 60;
        }
      }
      final cut = Classic.removeUniformBackground(studio);
      check('Düz arka plan kaldırma', cut.rgba[3] == 0 && cut.rgba[(100 * 300 + 150) * 4 + 3] == 255);
      check('Çözünürlük yükseltme 2×', Classic.upscale(Ops.resize(src, 100, 75), 2).width == 200);
      check('Otomatik iyileştirme', Classic.enhance(src).width == 640);
    });

    await guard('Proje kayıt sistemi', () async {
      final db = await ProjectDatabase.open(p.join(temp!.path, 'test.db'));
      final store = ProjectStore(projectsDir: p.join(temp.path, 'Projeler'), database: db);
      await Directory(store.projectsDir).create(recursive: true);
      final png = ImageEngine.encodeSync(src, ExportFormat.png, 90);
      final info = await store.create(
        name: 'Test projesi',
        sourceBytes: png,
        sourceExtension: 'png',
        width: 640,
        height: 480,
        documentBuilder: (f) => EditDocument(sourceFile: f, sourceWidth: 640, sourceHeight: 480),
      );
      final d0 = (await store.load(info.id)).current;
      final d1 = d0.copyWith(adjustments: const Adjustments(contrast: 25));
      final d2 = d1.addLayer(const TextLayer(id: 't1', name: 'Başlık', cx: 320, cy: 100, text: 'Merhaba ğüşıöç'));
      await store.save(info, [d0, d1, d2], ['Açılış', 'Kontrast', 'Metin'], 2);
      final loaded = await store.load(info.id);
      check('Kaydet ve yeniden aç', loaded.history.length == 3 && loaded.index == 2 && loaded.current.layers.length == 1);
      final t = loaded.current.layers.first;
      check('Türkçe metin katmanı korunur', t is TextLayer && t.text == 'Merhaba ğüşıöç');
      check('Ayarlar korunur', loaded.current.adjustments.contrast == 25);
      final renamed = await store.rename(loaded.info, 'Yeni ad');
      check('Yeniden adlandırma', (await db.byId(info.id))?.name == 'Yeni ad' && renamed.name == 'Yeni ad');
      check('Son projeler listesi', (await db.recent()).any((x) => x.id == info.id));
      await store.delete(info.id);
      check('Proje silme', !(await Directory(store.folderOf(info.id)).exists()) && await db.byId(info.id) == null);
      await db.close();
    });

    await guard('Geri al / yinele', () async {
      final h = History<int>(0, limit: 5);
      for (var i = 1; i <= 7; i++) {
        h.push(i, 'adım $i');
      }
      final u = h.undo();
      final r = h.redo();
      check('Çok adımlı geçmiş ve sınır', h.length == 5 && u == 6 && r == 7);
    });

    await guard('GPU katman birleştirme', () async {
      final base = Raster.filled(400, 300, 0, 0, 0);
      await ExportService.compositeLayers(
        base,
        const [ShapeLayer(id: 's', name: 'Kare', cx: 200, cy: 150, shape: ShapeKind.rect, width: 100, height: 100, fill: 0xFFFF0000)],
        const {},
        400,
        300,
      );
      final i = (150 * 400 + 200) * 4;
      check('Şekil katmanı dışa aktarmaya işlenir', base.rgba[i] > 240 && base.rgba[i + 1] < 15);
    });

    await guard('Gizlilik ve AI hataları', () async {
      final fake = _CountingProvider();
      final service = AiService(consent: (_) async => false);
      var cancelled = false;
      try {
        await service.run(fake, AiRequest(task: AiTask.removeBackground, image: src), progress: (_, __) {}, cancel: CancelToken());
      } on OperationCancelled {
        cancelled = true;
      }
      check('İzin verilmezse görsel gönderilmez', cancelled && fake.calls == 0);

      final offline = HuggingFaceProvider(token: 'hf_test', baseUrl: 'http://127.0.0.1:9/models', clientFactory: http.Client.new);
      String? msg;
      try {
        await offline.run(AiRequest(task: AiTask.upscale, image: Ops.resize(src, 64, 48)), progress: (_, __) {}, cancel: CancelToken());
      } on UserFacingException catch (e) {
        msg = e.message;
      }
      check('Bağlantı yokken anlaşılır hata', msg != null && msg.contains('ağlan'), msg);
    });

    await guard('Komut yorumlayıcı', () async {
      final r = CommandParser.parse('daha parlak ve siyah beyaz yap', Adjustments.none, Geometry.identity);
      check('"daha parlak ve siyah beyaz yap"', r.adjustments.exposure > 0 && r.adjustments.grayscale);
    });
  } catch (e, st) {
    check('Beklenmeyen hata', false, '$e\n$st');
  } finally {
    try {
      await temp?.delete(recursive: true);
    } catch (_) {}
  }

  lines
    ..add('')
    ..add('RESULT: ${passed ? 'PASS' : 'FAIL'}');
  await File(reportPath).writeAsString(lines.join('\n'), flush: true);
  return passed ? 0 : 1;
}

bool _throwsUser(void Function() f) {
  try {
    f();
    return false;
  } on UserFacingException {
    return true;
  } catch (_) {
    return false;
  }
}

/// Renk geçişi + yarı saydam daire içeren test görüntüsü.
Raster syntheticImage(int w, int h) {
  final r = Raster(w, h);
  final d = r.rgba;
  final cx = w / 2, cy = h / 2, rad = math.min(w, h) / 5;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final i = (y * w + x) * 4;
      d[i] = (x * 255 ~/ math.max(1, w - 1));
      d[i + 1] = (y * 255 ~/ math.max(1, h - 1));
      d[i + 2] = ((x + y) * 3) & 255;
      final dx = x - cx, dy = y - cy;
      d[i + 3] = dx * dx + dy * dy < rad * rad ? 160 : 255;
    }
  }
  return r;
}

double meanAbsDiff(Raster a, Raster b, {bool ignoreAlpha = false}) {
  if (a.width != b.width || a.height != b.height) return 999;
  var sum = 0;
  var n = 0;
  for (var i = 0; i < a.rgba.length; i += 4) {
    // Şeffaf olmayan formatlarda yarı saydam bölgeler karşılaştırılmaz.
    if (ignoreAlpha && a.rgba[i + 3] != 255) continue;
    for (var c = 0; c < (ignoreAlpha ? 3 : 4); c++) {
      sum += (a.rgba[i + c] - b.rgba[i + c]).abs();
      n++;
    }
  }
  return n == 0 ? 0 : sum / n;
}

class _CountingProvider extends AiProvider {
  int calls = 0;

  @override
  String get id => 'sayac';
  @override
  String get name => 'Sayaç (test)';
  @override
  bool get isOnline => true;
  @override
  bool get isConfigured => true;
  @override
  String get configurationHint => '';
  @override
  Set<AiTask> get supportedTasks => AiTask.values.toSet();
  @override
  ProviderPrivacy get privacy =>
      const ProviderPrivacy(host: 'ornek.test', dataHandling: 'test', policyUrl: 'https://ornek.test', limits: 'test');

  @override
  Future<AiResult> run(AiRequest request, {required ProgressCallback progress, required CancelToken cancel}) async {
    calls++;
    return AiResult(image: request.image, providerName: name);
  }
}
