import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../image_engine/geometry.dart';
import '../layers/layer.dart';
import '../layers/layer_painter.dart';
import 'editor_controller.dart';

/// Görünüm (yakınlaştırma + kaydırma) durumu. Ekran = belge * scale + offset.
class ViewportController extends ChangeNotifier {
  double scale = 1;
  Offset offset = Offset.zero;
  Size viewport = Size.zero;
  Size content = Size.zero;
  bool _fitted = false;
  double devicePixelRatio = 1;

  static const double minScale = 0.02;
  static const double maxScale = 32;

  Offset toDoc(Offset screen) => (screen - offset) / scale;
  Offset toScreen(Offset doc) => doc * scale + offset;

  /// Görünür yüzde (100% = 1 görüntü pikseli = 1 ekran pikseli).
  double get zoomPercent => scale * devicePixelRatio * 100;

  void configure(Size viewportSize, Size contentSize, double dpr) {
    devicePixelRatio = dpr;
    final contentChanged = (contentSize.width - content.width).abs() > 0.5 || (contentSize.height - content.height).abs() > 0.5;
    final viewportChanged = viewportSize != viewport;
    viewport = viewportSize;
    content = contentSize;
    if (!_fitted || contentChanged) {
      fit(notify: false);
    } else if (viewportChanged) {
      _clampOffset();
    }
  }

  void fit({bool notify = true}) {
    if (viewport.isEmpty || content.isEmpty) return;
    const margin = 28.0;
    final sx = (viewport.width - margin * 2) / content.width;
    final sy = (viewport.height - margin * 2) / content.height;
    scale = math.max(minScale, math.min(sx, sy));
    offset = Offset((viewport.width - content.width * scale) / 2, (viewport.height - content.height * scale) / 2);
    _fitted = true;
    if (notify) notifyListeners();
  }

  void zoomTo(double newScale, Offset focal) {
    final s = newScale.clamp(minScale, maxScale).toDouble();
    final doc = toDoc(focal);
    scale = s;
    offset = focal - doc * s;
    _clampOffset();
    notifyListeners();
  }

  void zoomBy(double factor, [Offset? focal]) => zoomTo(scale * factor, focal ?? viewport.center(Offset.zero));

  void actualPixels() => zoomTo(1 / devicePixelRatio, viewport.center(Offset.zero));

  void panBy(Offset delta) {
    offset += delta;
    _clampOffset();
    notifyListeners();
  }

  /// İçeriğin tamamen görünümden çıkmasını engeller.
  void _clampOffset() {
    final w = content.width * scale, h = content.height * scale;
    const keep = 80.0;
    final minX = keep - w, maxX = viewport.width - keep;
    final minY = keep - h, maxY = viewport.height - keep;
    offset = Offset(offset.dx.clamp(math.min(minX, maxX), math.max(minX, maxX)).toDouble(),
        offset.dy.clamp(math.min(minY, maxY), math.max(minY, maxY)).toDouble());
  }
}

enum _Drag { none, pan, pinch, moveLayer, scaleLayer, rotateLayer, layerPinch, crop, mask, inpaint }

/// Düzenleme alanı: önizleme, katmanlar, kırpma ve fırça etkileşimleri.
class EditorCanvas extends StatefulWidget {
  const EditorCanvas({super.key, required this.controller, required this.viewport});

  final EditorController controller;
  final ViewportController viewport;

  @override
  State<EditorCanvas> createState() => _EditorCanvasState();
}

class _EditorCanvasState extends State<EditorCanvas> {
  _Drag _drag = _Drag.none;
  Offset? _hover;

  // Sürükleme başlangıç durumu
  Offset _startFocal = Offset.zero;
  double _startScale = 1;
  Offset _startOffset = Offset.zero;
  Layer? _startLayer;
  double _startDistance = 1;
  double _startAngle = 0;
  int _cropHandle = -1; // 0-3 köşeler (sol-üst, sağ-üst, sağ-alt, sol-alt), 4-7 kenarlar, 8 iç
  NormRect? _startCrop;
  bool _middlePan = false;

  EditorController get c => widget.controller;
  ViewportController get v => widget.viewport;

  // ------------------------------------------------------------ İsabet testleri

  Rect get _cropDocRect {
    final s = c.displaySize;
    final r = c.cropDraft ?? NormRect.full;
    return Rect.fromLTRB(r.left * s.width, r.top * s.height, r.right * s.width, r.bottom * s.height);
  }

  int _hitCropHandle(Offset screen) {
    final r = _cropDocRect;
    final pts = [
      r.topLeft, r.topRight, r.bottomRight, r.bottomLeft, //
      r.topCenter, r.centerRight, r.bottomCenter, r.centerLeft,
    ];
    const tol = 22.0;
    for (var i = 0; i < pts.length; i++) {
      if (i >= 4 && c.cropAspectRatio != null) continue; // oran kilitliyken yalnızca köşeler
      if ((v.toScreen(pts[i]) - screen).distance <= tol) return i;
    }
    if (r.contains(v.toDoc(screen))) return 8;
    return -1;
  }

  /// Seçili katmanın tutamaçları (ekran koordinatı): [ölçek, döndürme]
  (Offset, Offset)? _handles() {
    final l = c.selectedLayer;
    if (l == null || !l.visible || c.tool != EditorTool.select) return null;
    final corners = LayerPainter.corners(l).map(v.toScreen).toList();
    final topMid = Offset((corners[0].dx + corners[1].dx) / 2, (corners[0].dy + corners[1].dy) / 2);
    final center = v.toScreen(Offset(l.cx, l.cy));
    final dir = topMid - center;
    final len = dir.distance;
    final rotate = len < 1 ? topMid - const Offset(0, 30) : topMid + dir / len * 30;
    return (corners[2], rotate);
  }

  Layer? _hitLayer(Offset doc) {
    final tol = 6 / v.scale;
    for (final l in c.doc.layers.reversed) {
      if (!l.locked && LayerPainter.hitTest(l, doc, tolerance: tol)) return l;
    }
    return null;
  }

  // ------------------------------------------------------------ Hareketler

  void _onScaleStart(ScaleStartDetails d) {
    if (_middlePan) return;
    _startFocal = d.localFocalPoint;
    _startScale = v.scale;
    _startOffset = v.offset;
    final doc = v.toDoc(d.localFocalPoint);

    if (d.pointerCount >= 2) {
      final sel = c.selectedLayer;
      if (c.tool == EditorTool.select && sel != null && !sel.locked && LayerPainter.hitTest(sel, doc, tolerance: 40 / v.scale)) {
        _drag = _Drag.layerPinch;
        _startLayer = sel;
      } else {
        _cancelBrushStroke();
        _drag = _Drag.pinch;
      }
      return;
    }

    switch (c.tool) {
      case EditorTool.crop:
        _cropHandle = _hitCropHandle(d.localFocalPoint);
        if (_cropHandle >= 0) {
          _drag = _Drag.crop;
          _startCrop = c.cropDraft ?? NormRect.full;
        } else {
          _drag = _Drag.pan;
        }
      case EditorTool.mask:
        if (c.selectedLayer != null) {
          _drag = _Drag.mask;
          c.maskStrokeStart(doc);
        } else {
          _drag = _Drag.pan;
        }
      case EditorTool.inpaint:
        _drag = _Drag.inpaint;
        c.inpaintStrokeStart(doc);
      default:
        final h = _handles();
        final sel = c.selectedLayer;
        if (h != null && sel != null && !sel.locked) {
          if ((h.$2 - d.localFocalPoint).distance < 20) {
            _drag = _Drag.rotateLayer;
            _startLayer = sel;
            final center = v.toScreen(Offset(sel.cx, sel.cy));
            _startAngle = (d.localFocalPoint - center).direction;
            return;
          }
          if ((h.$1 - d.localFocalPoint).distance < 20) {
            _drag = _Drag.scaleLayer;
            _startLayer = sel;
            final center = v.toScreen(Offset(sel.cx, sel.cy));
            _startDistance = math.max(1, (d.localFocalPoint - center).distance);
            return;
          }
        }
        final hit = _hitLayer(doc);
        if (hit != null) {
          if (hit.id != c.selectedLayerId) c.selectLayer(hit.id);
          if (c.tool != EditorTool.select) c.setTool(EditorTool.select);
          _drag = _Drag.moveLayer;
          _startLayer = hit;
        } else {
          if (c.tool == EditorTool.select && c.selectedLayerId != null) c.selectLayer(null);
          _drag = _Drag.pan;
        }
    }
  }

  void _cancelBrushStroke() {
    if (_drag == _Drag.mask) c.maskStrokeEnd();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_middlePan) return;
    final docNow = v.toDoc(d.localFocalPoint);
    switch (_drag) {
      case _Drag.pan:
        v.offset = _startOffset + (d.localFocalPoint - _startFocal);
        v.panBy(Offset.zero);
      case _Drag.pinch:
        final newScale = (_startScale * d.scale).clamp(ViewportController.minScale, ViewportController.maxScale).toDouble();
        final docAtStart = (_startFocal - _startOffset) / _startScale;
        v.scale = newScale;
        v.offset = d.localFocalPoint - docAtStart * newScale;
        v.panBy(Offset.zero);
      case _Drag.moveLayer:
        final l = _startLayer!;
        final delta = (d.localFocalPoint - _startFocal) / v.scale;
        c.previewLayer(l.copyBase(cx: l.cx + delta.dx, cy: l.cy + delta.dy));
      case _Drag.scaleLayer:
        final l = _startLayer!;
        final center = v.toScreen(Offset(l.cx, l.cy));
        final dist = (d.localFocalPoint - center).distance;
        final ns = (l.scale * dist / _startDistance).clamp(0.02, 50.0).toDouble();
        c.previewLayer(l.copyBase(scale: ns));
      case _Drag.rotateLayer:
        final l = _startLayer!;
        final center = v.toScreen(Offset(l.cx, l.cy));
        var angle = l.rotation + (d.localFocalPoint - center).direction - _startAngle;
        // 15°'lik adımlara yakınsa yapış
        final deg = angle * 180 / math.pi;
        final snapped = (deg / 15).round() * 15;
        if ((deg - snapped).abs() < 2.5) angle = snapped * math.pi / 180;
        c.previewLayer(l.copyBase(rotation: angle));
      case _Drag.layerPinch:
        final l = _startLayer!;
        final delta = (d.localFocalPoint - _startFocal) / v.scale;
        c.previewLayer(l.copyBase(
          scale: (l.scale * d.scale).clamp(0.02, 50.0).toDouble(),
          rotation: l.rotation + d.rotation,
          cx: l.cx + delta.dx,
          cy: l.cy + delta.dy,
        ));
      case _Drag.crop:
        _updateCrop(docNow);
      case _Drag.mask:
        c.maskStrokeUpdate(docNow);
      case _Drag.inpaint:
        c.inpaintStrokeUpdate(docNow);
      case _Drag.none:
        break;
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    switch (_drag) {
      case _Drag.moveLayer:
        if (!identical(c.doc, c.history.current)) c.commit('Katmanı taşı');
      case _Drag.scaleLayer:
      case _Drag.layerPinch:
        if (!identical(c.doc, c.history.current)) c.commit('Katmanı dönüştür');
      case _Drag.rotateLayer:
        if (!identical(c.doc, c.history.current)) c.commit('Katmanı döndür');
      case _Drag.mask:
        c.maskStrokeEnd();
      default:
        break;
    }
    _drag = _Drag.none;
    _startLayer = null;
  }

  void _updateCrop(Offset doc) {
    final s = c.displaySize;
    final start = _startCrop!;
    final p = Offset((doc.dx / s.width).clamp(0.0, 1.0).toDouble(), (doc.dy / s.height).clamp(0.0, 1.0).toDouble());
    final startDoc = v.toDoc(_startFocal);
    final dn = Offset((doc.dx - startDoc.dx) / s.width, (doc.dy - startDoc.dy) / s.height);
    var l = start.left, t = start.top, r = start.right, b = start.bottom;
    const minN = 0.02;
    final ratio = c.cropAspectRatio;
    switch (_cropHandle) {
      case 8:
        final w = r - l, h = b - t;
        l = (start.left + dn.dx).clamp(0.0, 1 - w).toDouble();
        t = (start.top + dn.dy).clamp(0.0, 1 - h).toDouble();
        r = l + w;
        b = t + h;
      case 0:
      case 1:
      case 2:
      case 3:
        // Karşı köşe sabit
        final ax = (_cropHandle == 0 || _cropHandle == 3) ? start.right : start.left;
        final ay = (_cropHandle == 0 || _cropHandle == 1) ? start.bottom : start.top;
        var nx = p.dx, ny = p.dy;
        if (ratio != null) {
          // Piksel oranını koru
          var wPx = (nx - ax).abs() * s.width;
          var hPx = (ny - ay).abs() * s.height;
          if (wPx / ratio > hPx) {
            hPx = wPx / ratio;
          } else {
            wPx = hPx * ratio;
          }
          // Sınır içinde kal
          final maxW = (nx < ax ? ax : 1 - ax) * s.width;
          final maxH = (ny < ay ? ay : 1 - ay) * s.height;
          if (wPx > maxW) {
            wPx = maxW;
            hPx = wPx / ratio;
          }
          if (hPx > maxH) {
            hPx = maxH;
            wPx = hPx * ratio;
          }
          nx = nx < ax ? ax - wPx / s.width : ax + wPx / s.width;
          ny = ny < ay ? ay - hPx / s.height : ay + hPx / s.height;
        }
        l = math.min(ax, nx);
        r = math.max(ax, nx);
        t = math.min(ay, ny);
        b = math.max(ay, ny);
      case 4:
        t = math.min(p.dy, b - minN);
      case 5:
        r = math.max(p.dx, l + minN);
      case 6:
        b = math.max(p.dy, t + minN);
      case 7:
        l = math.min(p.dx, r - minN);
    }
    if (r - l < minN || b - t < minN) return;
    c.setCropDraft(NormRect(l, t, r, b));
  }

  // ------------------------------------------------------------ İşaretçi olayları

  void _onPointerSignal(PointerSignalEvent e) {
    if (e is PointerScrollEvent) {
      final factor = math.exp(-e.scrollDelta.dy / 420);
      v.zoomBy(factor, e.localPosition);
    }
  }

  void _onPointerDown(PointerDownEvent e) {
    if (e.kind == PointerDeviceKind.mouse && (e.buttons & (kMiddleMouseButton | kSecondaryMouseButton)) != 0) {
      _middlePan = true;
    }
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (_middlePan) v.panBy(e.delta);
    if (e.kind == PointerDeviceKind.mouse) setState(() => _hover = e.localPosition);
  }

  void _onPointerUp(PointerEvent e) {
    _middlePan = false;
  }

  MouseCursor get _cursor {
    switch (c.tool) {
      case EditorTool.mask:
      case EditorTool.inpaint:
        return SystemMouseCursors.precise;
      case EditorTool.crop:
        final h = _hover == null ? -1 : _hitCropHandle(_hover!);
        if (h == 8) return SystemMouseCursors.move;
        if (h == 0 || h == 2) return SystemMouseCursors.resizeUpLeftDownRight;
        if (h == 1 || h == 3) return SystemMouseCursors.resizeUpRightDownLeft;
        if (h == 4 || h == 6) return SystemMouseCursors.resizeUpDown;
        if (h == 5 || h == 7) return SystemMouseCursors.resizeLeftRight;
        return SystemMouseCursors.grab;
      default:
        if (_hover != null) {
          final h = _handles();
          if (h != null) {
            if ((h.$2 - _hover!).distance < 20) return SystemMouseCursors.alias;
            if ((h.$1 - _hover!).distance < 20) return SystemMouseCursors.resizeUpLeftDownRight;
          }
          if (_hitLayer(v.toDoc(_hover!)) != null) return SystemMouseCursors.move;
        }
        return SystemMouseCursors.basic;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final size = Size(constraints.maxWidth, constraints.maxHeight);
      v.configure(size, c.displaySize, MediaQuery.devicePixelRatioOf(context));
      return ClipRect(
        child: MouseRegion(
          cursor: _cursor,
          onHover: (e) => setState(() => _hover = e.localPosition),
          onExit: (_) => setState(() => _hover = null),
          child: Listener(
            onPointerSignal: _onPointerSignal,
            onPointerDown: _onPointerDown,
            onPointerMove: _onPointerMove,
            onPointerUp: _onPointerUp,
            onPointerCancel: _onPointerUp,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              onDoubleTap: () {
                final sel = c.selectedLayer;
                if (sel is TextLayer) return; // metin düzenleme paneli zaten açık
                v.fit();
              },
              child: ListenableBuilder(
                listenable: Listenable.merge([c, v]),
                builder: (context, _) => CustomPaint(
                  size: size,
                  painter: _CanvasPainter(c, v, _hover),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _CanvasPainter extends CustomPainter {
  _CanvasPainter(this.c, this.v, this.hover);

  final EditorController c;
  final ViewportController v;
  final Offset? hover;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = PxColors.canvas);
    final docSize = c.displaySize;
    final docRect = Offset.zero & docSize;
    final inCrop = c.tool == EditorTool.crop;

    canvas.save();
    canvas.translate(v.offset.dx, v.offset.dy);
    canvas.scale(v.scale);

    // Gölge + dama tahtası (şeffaflık)
    canvas.drawRect(docRect.inflate(1 / v.scale), Paint()..color = const Color(0xFF000000));
    _checkerboard(canvas, docRect);

    final img = inCrop ? (c.cropImage ?? c.baseImage) : c.baseImage;
    if (img != null) {
      canvas.drawImageRect(
        img,
        Rect.fromLTWH(0, 0, img.width.toDouble(), img.height.toDouble()),
        docRect,
        Paint()
          ..filterQuality = v.scale * v.devicePixelRatio < 1 ? FilterQuality.medium : FilterQuality.low
          ..colorFilter = ColorFilter.matrix(c.colorMatrix),
      );
    }

    if (!inCrop) {
      canvas.save();
      canvas.clipRect(docRect);
      LayerPainter.paintLayers(canvas, c.doc.layers, c.layerImages,
          maskOverlayFor: c.tool == EditorTool.mask && c.showMaskOverlay ? c.selectedLayerId : null);
      canvas.restore();
      if (c.inpaintStrokes.isNotEmpty) _paintInpaint(canvas);
    }
    canvas.restore();

    if (inCrop) {
      _paintCrop(canvas, size, docSize);
    } else {
      _paintSelection(canvas);
      _paintBrushCursor(canvas);
    }
  }

  void _checkerboard(Canvas canvas, Rect r) {
    final cell = 12 / v.scale;
    final p1 = Paint()..color = const Color(0xFF2B2F3B);
    final p2 = Paint()..color = const Color(0xFF1E212A);
    canvas.drawRect(r, p2);
    // Görünür alanla sınırlı çizim
    final visible = Rect.fromLTWH(-v.offset.dx / v.scale, -v.offset.dy / v.scale, v.viewport.width / v.scale,
            v.viewport.height / v.scale)
        .intersect(r);
    if (visible.isEmpty) return;
    final x0 = (visible.left / cell).floor(), x1 = (visible.right / cell).ceil();
    final y0 = (visible.top / cell).floor(), y1 = (visible.bottom / cell).ceil();
    if ((x1 - x0) * (y1 - y0) > 40000) return;
    canvas.save();
    canvas.clipRect(r);
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        if ((x + y).isEven) canvas.drawRect(Rect.fromLTWH(x * cell, y * cell, cell, cell), p1);
      }
    }
    canvas.restore();
  }

  void _paintInpaint(Canvas canvas) {
    final paint = Paint()
      ..color = const Color(0x88FF3B5C)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    canvas.saveLayer(null, Paint()..color = const Color(0xB0FFFFFF));
    for (final s in c.inpaintStrokes) {
      paint.strokeWidth = s[0] * 2;
      final path = Path()..moveTo(s[1], s[2]);
      if (s.length == 3) {
        path.lineTo(s[1] + 0.01, s[2]);
      } else {
        for (var i = 3; i + 1 < s.length; i += 2) {
          path.lineTo(s[i], s[i + 1]);
        }
      }
      canvas.drawPath(path, paint..color = const Color(0xFFFF3B5C));
    }
    canvas.restore();
  }

  void _paintSelection(Canvas canvas) {
    final l = c.selectedLayer;
    if (l == null || !l.visible) return;
    final pts = LayerPainter.corners(l).map(v.toScreen).toList();
    final path = Path()..addPolygon(pts, true);
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..color = l.locked ? PxColors.muted : PxColors.accent,
    );
    if (l.locked || c.tool != EditorTool.select) return;
    final fill = Paint()..color = Colors.white;
    final border = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = PxColors.primary;
    for (final p in pts) {
      canvas.drawRect(Rect.fromCenter(center: p, width: 9, height: 9), fill);
      canvas.drawRect(Rect.fromCenter(center: p, width: 9, height: 9), border);
    }
    // Ölçek tutamacı (sağ-alt, büyük) ve döndürme tutamacı
    canvas.drawCircle(pts[2], 8, fill);
    canvas.drawCircle(pts[2], 8, border);
    final topMid = Offset((pts[0].dx + pts[1].dx) / 2, (pts[0].dy + pts[1].dy) / 2);
    final center = v.toScreen(Offset(l.cx, l.cy));
    final dir = topMid - center;
    final rot = dir.distance < 1 ? topMid - const Offset(0, 30) : topMid + dir / dir.distance * 30;
    canvas.drawLine(topMid, rot, border);
    canvas.drawCircle(rot, 8, Paint()..color = PxColors.primary);
    canvas.drawCircle(rot, 3, fill);
  }

  void _paintBrushCursor(Canvas canvas) {
    final h = hover;
    if (h == null) return;
    double? r;
    if (c.tool == EditorTool.mask) r = c.maskBrush * v.scale;
    if (c.tool == EditorTool.inpaint) r = c.inpaintBrush * v.scale;
    if (r == null) return;
    canvas.drawCircle(h, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = const Color(0xAA000000));
    canvas.drawCircle(h, r, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = Colors.white);
  }

  void _paintCrop(Canvas canvas, Size size, Size docSize) {
    final r = c.cropDraft ?? NormRect.full;
    final docCrop = Rect.fromLTRB(r.left * docSize.width, r.top * docSize.height, r.right * docSize.width, r.bottom * docSize.height);
    final screen = Rect.fromPoints(v.toScreen(docCrop.topLeft), v.toScreen(docCrop.bottomRight));
    final imageRect = Rect.fromPoints(v.toScreen(Offset.zero), v.toScreen(Offset(docSize.width, docSize.height)));
    final dim = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(imageRect)
      ..addRect(screen);
    canvas.drawPath(dim, Paint()..color = const Color(0xB0000000));
    final line = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = const Color(0x88FFFFFF);
    for (var i = 1; i < 3; i++) {
      final x = screen.left + screen.width * i / 3;
      final y = screen.top + screen.height * i / 3;
      canvas.drawLine(Offset(x, screen.top), Offset(x, screen.bottom), line);
      canvas.drawLine(Offset(screen.left, y), Offset(screen.right, y), line);
    }
    canvas.drawRect(screen, Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..color = Colors.white);
    final handle = Paint()..color = Colors.white;
    const hl = 18.0, hw = 4.0;
    for (final corner in [screen.topLeft, screen.topRight, screen.bottomRight, screen.bottomLeft]) {
      final sx = corner.dx == screen.left ? 1.0 : -1.0;
      final sy = corner.dy == screen.top ? 1.0 : -1.0;
      canvas.drawRect(Rect.fromLTWH(corner.dx - (sx < 0 ? hw : 0), corner.dy - (sy < 0 ? hw : 0), hw, hl * sy), handle);
      canvas.drawRect(Rect.fromLTWH(corner.dx - (sx < 0 ? hw : 0), corner.dy - (sy < 0 ? hw : 0), hl * sx, hw), handle);
    }
    if (c.cropAspectRatio == null) {
      for (final m in [screen.topCenter, screen.centerRight, screen.bottomCenter, screen.centerLeft]) {
        canvas.drawRRect(RRect.fromRectAndRadius(Rect.fromCenter(center: m, width: 16, height: 16), const Radius.circular(3)),
            handle);
      }
    }
    // Boyut etiketi
    final w = (r.width * docSize.width).round(), h = (r.height * docSize.height).round();
    final tp = TextPainter(
      text: TextSpan(text: '$w × $h', style: const TextStyle(color: Colors.white, fontSize: 12, fontFamily: 'Inter')),
      textDirection: TextDirection.ltr,
    )..layout();
    final label = Rect.fromLTWH(screen.left, screen.top - 26, tp.width + 14, 22);
    canvas.drawRRect(RRect.fromRectAndRadius(label, const Radius.circular(6)), Paint()..color = const Color(0xCC000000));
    tp.paint(canvas, label.topLeft + const Offset(7, 4));
  }

  @override
  bool shouldRepaint(_CanvasPainter old) => true;
}

/// Görsel yükleme/işleme göstergesi (sağ üst köşe).
class RenderIndicator extends StatelessWidget {
  const RenderIndicator({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        // Gizliyken sonsuz animasyon oluşturulmaz (pil ve test kararlılığı için).
        if (!controller.rendering) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(color: const Color(0xCC111522), borderRadius: BorderRadius.circular(20)),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
              SizedBox(width: 8),
              Text('İşleniyor', style: TextStyle(fontSize: 12)),
            ],
          ),
        );
      },
    );
  }
}

// ui importu yalnızca tür için (lint uyarısını önlemek amacıyla kullanılır).
typedef UiImage = ui.Image;
