import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import '../image_engine/raster.dart';

/// [Raster] <-> `ui.Image` dönüşümleri (GPU dokusu).
class UiImages {
  UiImages._();

  static Future<ui.Image> fromRaster(Raster r) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(r.rgba, r.width, r.height, ui.PixelFormat.rgba8888, completer.complete);
    return completer.future;
  }

  static Future<Raster> toRaster(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.rawStraightRgba);
    if (data == null) throw StateError('Görüntü verisi okunamadı');
    return Raster(image.width, image.height, Uint8List.fromList(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes)));
  }

  static Future<Uint8List> toPng(ui.Image image) async {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('PNG oluşturulamadı');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}
