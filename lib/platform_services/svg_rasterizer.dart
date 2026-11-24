import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_svg/flutter_svg.dart';

import '../core/errors.dart';
import '../image_engine/raster.dart';
import 'ui_images.dart';

/// SVG vektör çizimini piksel görüntüye dönüştürür (Flutter gerektirir,
/// bu nedenle arayüz isolate'inde çalışır).
class SvgRasterizer {
  SvgRasterizer._();

  static Future<Raster> rasterize(Uint8List bytes, {int longSide = 2048}) async {
    PictureInfo info;
    try {
      info = await vg.loadPicture(SvgBytesLoader(bytes), null);
    } catch (e) {
      throw UserFacingException('SVG dosyası okunamadı: geçersiz veya desteklenmeyen SVG içeriği.', details: '$e');
    }
    try {
      var w = info.size.width, h = info.size.height;
      if (w <= 0 || h <= 0) {
        w = 1024;
        h = 1024;
      }
      final scale = longSide / (w > h ? w : h);
      final outW = (w * scale).round().clamp(1, 8192);
      final outH = (h * scale).round().clamp(1, 8192);
      final recorder = ui.PictureRecorder();
      final canvas = ui.Canvas(recorder);
      canvas.scale(outW / w, outH / h);
      canvas.drawPicture(info.picture);
      final picture = recorder.endRecording();
      final image = await picture.toImage(outW, outH);
      picture.dispose();
      final raster = await UiImages.toRaster(image);
      image.dispose();
      return raster;
    } finally {
      info.picture.dispose();
    }
  }
}
