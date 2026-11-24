import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'layer.dart';

/// Katman görsellerinin (ui.Image) önbelleği. Önizlemede küçültülmüş,
/// dışa aktarmada tam çözünürlüklü görseller kullanılır.
typedef LayerImages = Map<String, ui.Image>;

/// Katmanları hem ekranda hem dışa aktarmada çizen TEK kod yolu.
/// Önizleme ile kaydedilen dosyanın aynı görünmesinin güvencesidir.
class LayerPainter {
  LayerPainter._();

  static final Expando<_TextLayout> _textCache = Expando('textLayout');

  static FontWeight _weight(TextLayer l) => l.bold ? FontWeight.w700 : FontWeight.w400;

  static _TextLayout _layout(TextLayer l) {
    final cached = _textCache[l];
    if (cached != null) return cached;
    final align = switch (l.align) {
      TextAlignOption.left => TextAlign.left,
      TextAlignOption.center => TextAlign.center,
      TextAlignOption.right => TextAlign.right,
    };
    TextStyle style({Paint? foreground, List<Shadow>? shadows, Color? color}) => TextStyle(
          fontFamily: l.isSticker ? null : l.fontFamily,
          fontSize: l.fontSize,
          fontWeight: _weight(l),
          fontStyle: l.italic ? FontStyle.italic : FontStyle.normal,
          letterSpacing: l.letterSpacing,
          height: l.lineHeight,
          color: foreground == null ? color : null,
          foreground: foreground,
          shadows: shadows,
        );
    final text = l.text.isEmpty ? ' ' : l.text;
    final maxWidth = l.boxWidth > 0 ? l.boxWidth : double.infinity;
    final fill = TextPainter(
      text: TextSpan(
        text: text,
        style: style(
          color: Color(l.color),
          shadows: l.shadow && l.strokeWidth <= 0
              ? [Shadow(color: Color(l.shadowColor), blurRadius: l.fontSize * 0.12, offset: Offset(0, l.fontSize * 0.05))]
              : null,
        ),
      ),
      textAlign: align,
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: maxWidth);
    TextPainter? stroke;
    if (l.strokeWidth > 0) {
      stroke = TextPainter(
        text: TextSpan(
          text: text,
          style: style(
            foreground: Paint()
              ..style = PaintingStyle.stroke
              ..strokeWidth = l.strokeWidth
              ..strokeJoin = StrokeJoin.round
              ..color = Color(l.strokeColor),
            shadows: l.shadow
                ? [Shadow(color: Color(l.shadowColor), blurRadius: l.fontSize * 0.12, offset: Offset(0, l.fontSize * 0.05))]
                : null,
          ),
        ),
        textAlign: align,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: maxWidth);
    }
    final w = (l.boxWidth > 0 ? l.boxWidth : fill.width) + l.padding * 2 + l.strokeWidth;
    final h = fill.height + l.padding * 2 + l.strokeWidth;
    final layout = _TextLayout(fill, stroke, Size(math.max(1.0, w), math.max(1.0, h)));
    _textCache[l] = layout;
    return layout;
  }

  /// Katmanın ölçeklenmemiş içerik boyutu.
  static Size contentSize(Layer l) {
    if (l is TextLayer) return _layout(l).size;
    if (l is ImageLayer) return Size(l.width, l.height);
    if (l is ShapeLayer) return Size(l.width, l.height);
    return const Size(1, 1);
  }

  /// Belge koordinatından katman yerel koordinatına.
  static Offset toLocal(Layer l, Offset doc) {
    final dx = doc.dx - l.cx, dy = doc.dy - l.cy;
    final c = math.cos(-l.rotation), s = math.sin(-l.rotation);
    final rx = dx * c - dy * s, ry = dx * s + dy * c;
    final sc = l.scale == 0 ? 1 : l.scale;
    return Offset(rx / sc, ry / sc);
  }

  static Offset toDoc(Layer l, Offset local) {
    final x = local.dx * l.scale, y = local.dy * l.scale;
    final c = math.cos(l.rotation), s = math.sin(l.rotation);
    return Offset(x * c - y * s + l.cx, x * s + y * c + l.cy);
  }

  static bool hitTest(Layer l, Offset doc, {double tolerance = 0}) {
    if (!l.visible) return false;
    final local = toLocal(l, doc);
    final size = contentSize(l);
    final t = tolerance / (l.scale == 0 ? 1 : l.scale);
    return local.dx.abs() <= size.width / 2 + t && local.dy.abs() <= size.height / 2 + t;
  }

  /// Belge koordinatlarında dört köşe (sol-üst, sağ-üst, sağ-alt, sol-alt).
  static List<Offset> corners(Layer l) {
    final s = contentSize(l);
    final hw = s.width / 2, hh = s.height / 2;
    return [
      toDoc(l, Offset(-hw, -hh)),
      toDoc(l, Offset(hw, -hh)),
      toDoc(l, Offset(hw, hh)),
      toDoc(l, Offset(-hw, hh)),
    ];
  }

  static BlendMode blendMode(LayerBlend b) => switch (b) {
        LayerBlend.normal => BlendMode.srcOver,
        LayerBlend.multiply => BlendMode.multiply,
        LayerBlend.screen => BlendMode.screen,
        LayerBlend.overlay => BlendMode.overlay,
        LayerBlend.darken => BlendMode.darken,
        LayerBlend.lighten => BlendMode.lighten,
        LayerBlend.colorDodge => BlendMode.colorDodge,
        LayerBlend.colorBurn => BlendMode.colorBurn,
        LayerBlend.hardLight => BlendMode.hardLight,
        LayerBlend.softLight => BlendMode.softLight,
        LayerBlend.difference => BlendMode.difference,
        LayerBlend.exclusion => BlendMode.exclusion,
        LayerBlend.hue => BlendMode.hue,
        LayerBlend.saturation => BlendMode.saturation,
        LayerBlend.color => BlendMode.color,
        LayerBlend.luminosity => BlendMode.luminosity,
      };

  static void paintLayers(Canvas canvas, List<Layer> layers, LayerImages images, {String? maskOverlayFor}) {
    for (final l in layers) {
      if (!l.visible) continue;
      paintLayer(canvas, l, images, showMaskOverlay: l.id == maskOverlayFor);
    }
  }

  static void paintLayer(Canvas canvas, Layer l, LayerImages images, {bool showMaskOverlay = false}) {
    final size = contentSize(l);
    final rect = Rect.fromCenter(center: Offset.zero, width: size.width, height: size.height);
    final bleed = math.max(size.width, size.height) * 0.3 + 8;
    final bounds = rect.inflate(bleed);
    final hasMask = l.maskEnabled && l.mask.isNotEmpty;
    final needsLayer = l.opacity < 0.999 || l.blend != LayerBlend.normal || hasMask;

    canvas.save();
    canvas.translate(l.cx, l.cy);
    canvas.rotate(l.rotation);
    canvas.scale(l.scale);

    if (needsLayer) {
      canvas.saveLayer(
        bounds,
        Paint()
          ..color = Color.fromRGBO(0, 0, 0, l.opacity.clamp(0.0, 1.0).toDouble())
          ..blendMode = blendMode(l.blend),
      );
    }
    _paintContent(canvas, l, rect, images);
    if (hasMask) {
      canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstIn);
      _paintMask(canvas, l, bounds);
      canvas.restore();
    }
    if (needsLayer) canvas.restore();

    if (showMaskOverlay && l.mask.isNotEmpty) {
      // Gizlenen alanları yarı saydam kırmızıyla göster.
      canvas.saveLayer(bounds, Paint());
      canvas.drawRect(rect, Paint()..color = const Color(0x80FF3B5C));
      canvas.saveLayer(bounds, Paint()..blendMode = BlendMode.dstOut);
      _paintMask(canvas, l, bounds);
      canvas.restore();
      canvas.restore();
    }
    canvas.restore();
  }

  /// Maske: beyaz = görünür. Fırça (hide) dstOut ile siler, silgi geri boyar.
  static void _paintMask(Canvas canvas, Layer l, Rect bounds) {
    canvas.drawRect(bounds, Paint()..color = const Color(0xFFFFFFFF));
    for (final s in l.mask) {
      if (s.points.length < 2) continue;
      final paint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = s.radius * 2
        ..color = const Color(0xFFFFFFFF)
        ..blendMode = s.hide ? BlendMode.dstOut : BlendMode.srcOver;
      if (s.feather > 0) {
        paint.maskFilter = MaskFilter.blur(BlurStyle.normal, math.max(0.5, s.radius * s.feather * 0.5));
      }
      final path = Path()..moveTo(s.points[0], s.points[1]);
      if (s.points.length == 2) {
        path.lineTo(s.points[0] + 0.01, s.points[1]);
      } else {
        for (var i = 2; i + 1 < s.points.length; i += 2) {
          path.lineTo(s.points[i], s.points[i + 1]);
        }
      }
      canvas.drawPath(path, paint);
    }
  }

  static void _paintContent(Canvas canvas, Layer l, Rect rect, LayerImages images) {
    if (l is TextLayer) {
      _paintText(canvas, l, rect);
    } else if (l is ImageLayer) {
      _paintImage(canvas, l, rect, images[l.assetFile]);
    } else if (l is ShapeLayer) {
      _paintShape(canvas, l, rect);
    }
  }

  static void _paintText(Canvas canvas, TextLayer l, Rect rect) {
    final layout = _layout(l);
    if (l.background != 0) {
      final r = math.min(rect.height * 0.25, l.fontSize * 0.35);
      canvas.drawRRect(RRect.fromRectAndRadius(rect, Radius.circular(r)), Paint()..color = Color(l.background));
    }
    final inner = rect.deflate(l.padding + l.strokeWidth / 2);
    final contentWidth = inner.width;
    double dxFor(TextPainter tp) {
      if (l.boxWidth > 0) return inner.left;
      return inner.left + (contentWidth - tp.width) / 2;
    }

    if (layout.stroke != null) layout.stroke!.paint(canvas, Offset(dxFor(layout.stroke!), inner.top));
    layout.fill.paint(canvas, Offset(dxFor(layout.fill), inner.top));
  }

  static void _paintImage(Canvas canvas, ImageLayer l, Rect rect, ui.Image? image) {
    final rrect = RRect.fromRectAndRadius(rect, Radius.circular(l.cornerRadius));
    canvas.save();
    canvas.clipRRect(rrect);
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = const Color(0xFF2A2F3A));
      final p = Paint()
        ..color = const Color(0xFF4A5160)
        ..strokeWidth = math.max(2.0, rect.shortestSide / 60)
        ..style = PaintingStyle.stroke;
      canvas.drawLine(rect.topLeft, rect.bottomRight, p);
      canvas.drawLine(rect.topRight, rect.bottomLeft, p);
    } else {
      final iw = image.width.toDouble(), ih = image.height.toDouble();
      final boxAspect = rect.width / rect.height;
      double sw, sh;
      if (iw / ih > boxAspect) {
        sh = ih;
        sw = ih * boxAspect;
      } else {
        sw = iw;
        sh = iw / boxAspect;
      }
      sw /= l.contentScale;
      sh /= l.contentScale;
      final maxX = (iw - sw) / 2, maxY = (ih - sh) / 2;
      final center = Offset(iw / 2 + l.contentOffsetX * maxX, ih / 2 + l.contentOffsetY * maxY);
      final src = Rect.fromCenter(center: center, width: sw, height: sh);
      canvas.drawImageRect(image, src, rect, Paint()..filterQuality = FilterQuality.high);
    }
    canvas.restore();
    if (l.borderWidth > 0) {
      canvas.drawRRect(
        rrect.deflate(l.borderWidth / 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.borderWidth
          ..color = Color(l.borderColor),
      );
    }
  }

  static Path shapePath(ShapeKind kind, Rect r, double cornerRadius) {
    switch (kind) {
      case ShapeKind.rect:
      case ShapeKind.line:
        return Path()..addRect(r);
      case ShapeKind.roundRect:
        return Path()..addRRect(RRect.fromRectAndRadius(r, Radius.circular(math.min(cornerRadius, r.shortestSide / 2))));
      case ShapeKind.ellipse:
        return Path()..addOval(r);
      case ShapeKind.triangle:
        return Path()
          ..moveTo(r.center.dx, r.top)
          ..lineTo(r.right, r.bottom)
          ..lineTo(r.left, r.bottom)
          ..close();
      case ShapeKind.star:
        return _starPath(r, 5, 0.45);
      case ShapeKind.badge:
        return _starPath(r, 16, 0.82);
      case ShapeKind.heart:
        final w = r.width, h = r.height;
        return Path()
          ..moveTo(r.left + w / 2, r.top + h * 0.3)
          ..cubicTo(r.left + w * 0.5, r.top, r.left, r.top, r.left, r.top + h * 0.32)
          ..cubicTo(r.left, r.top + h * 0.6, r.left + w * 0.38, r.top + h * 0.78, r.left + w / 2, r.bottom)
          ..cubicTo(r.left + w * 0.62, r.top + h * 0.78, r.right, r.top + h * 0.6, r.right, r.top + h * 0.32)
          ..cubicTo(r.right, r.top, r.left + w * 0.5, r.top, r.left + w / 2, r.top + h * 0.3)
          ..close();
      case ShapeKind.arrow:
        final shaftH = r.height * 0.36;
        final headW = math.min(r.width * 0.45, r.height * 1.1);
        return Path()
          ..moveTo(r.left, r.center.dy - shaftH / 2)
          ..lineTo(r.right - headW, r.center.dy - shaftH / 2)
          ..lineTo(r.right - headW, r.top)
          ..lineTo(r.right, r.center.dy)
          ..lineTo(r.right - headW, r.bottom)
          ..lineTo(r.right - headW, r.center.dy + shaftH / 2)
          ..lineTo(r.left, r.center.dy + shaftH / 2)
          ..close();
      case ShapeKind.bubble:
        final body = Rect.fromLTRB(r.left, r.top, r.right, r.top + r.height * 0.78);
        final rad = math.min(cornerRadius.clamp(4.0, 400.0).toDouble(), body.shortestSide / 2);
        return Path()
          ..addRRect(RRect.fromRectAndRadius(body, Radius.circular(rad)))
          ..moveTo(r.left + r.width * 0.22, body.bottom - 1)
          ..lineTo(r.left + r.width * 0.18, r.bottom)
          ..lineTo(r.left + r.width * 0.42, body.bottom - 1)
          ..close();
    }
  }

  static Path _starPath(Rect r, int points, double innerRatio) {
    final path = Path();
    final cx = r.center.dx, cy = r.center.dy;
    final rx = r.width / 2, ry = r.height / 2;
    for (var i = 0; i < points * 2; i++) {
      final a = -math.pi / 2 + i * math.pi / points;
      final k = i.isEven ? 1.0 : innerRatio;
      final x = cx + math.cos(a) * rx * k, y = cy + math.sin(a) * ry * k;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    return path..close();
  }

  static void _paintShape(Canvas canvas, ShapeLayer l, Rect rect) {
    final path = shapePath(l.shape, rect, l.cornerRadius);
    final fill = Paint()..isAntiAlias = true;
    if (l.fillEnd != 0) {
      fill.shader = ui.Gradient.linear(rect.topCenter, rect.bottomCenter, [Color(l.fill), Color(l.fillEnd)]);
    } else {
      fill.color = Color(l.fill);
    }
    canvas.drawPath(path, fill);
    if (l.strokeWidth > 0 && (l.stroke >> 24) != 0) {
      canvas.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = l.strokeWidth
          ..strokeJoin = StrokeJoin.round
          ..color = Color(l.stroke),
      );
    }
  }
}

class _TextLayout {
  _TextLayout(this.fill, this.stroke, this.size);
  final TextPainter fill;
  final TextPainter? stroke;
  final Size size;
}
