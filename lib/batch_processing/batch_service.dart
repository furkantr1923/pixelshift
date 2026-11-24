import 'dart:isolate';
import 'dart:typed_data';

import '../filters/adjustments.dart';
import '../image_engine/classic.dart';
import '../image_engine/codec.dart';
import '../image_engine/engine.dart';
import '../image_engine/ops.dart';
import '../image_engine/raster.dart';

enum ResizeMode { none, maxSide, percent }

class BatchOptions {
  const BatchOptions({
    this.format = ExportFormat.jpg,
    this.quality = 90,
    this.resizeMode = ResizeMode.none,
    this.maxSide = 2048,
    this.percent = 50,
    this.filterId = 'none',
    this.autoEnhance = false,
    this.suffix = '_pixelshift',
  });

  final ExportFormat format;
  final int quality;
  final ResizeMode resizeMode;
  final int maxSide;
  final int percent;
  final String filterId;
  final bool autoEnhance;
  final String suffix;
}

class BatchOutput {
  const BatchOutput(this.bytes, this.fileName, this.width, this.height);
  final Uint8List bytes;
  final String fileName;
  final int width;
  final int height;
}

/// Tek bir dosyayı işler (çöz → boyutlandır → iyileştir/filtre → kodla).
/// Arka plan isolate'inde çalışır; dosyalar sırayla işlendiği için bellekte
/// aynı anda yalnızca bir görsel bulunur.
class BatchService {
  BatchService._();

  static Future<BatchOutput> process(Uint8List bytes, String fileName, BatchOptions o) =>
      Isolate.run(() => processSync(bytes, fileName, o));

  static BatchOutput processSync(Uint8List bytes, String fileName, BatchOptions o) {
    var r = ImageCodec.decode(bytes, fileName);
    r = _resize(r, o);
    if (o.autoEnhance) r = Classic.enhance(r);
    if (o.filterId != 'none') {
      final a = Adjustments(filterId: o.filterId);
      r = ImageEngine.applyDetail(r, a);
      a.colorMatrix().applyTo(r);
    }
    final out = ImageEngine.encodeSync(r, o.format, o.quality);
    return BatchOutput(out, outputName(fileName, o), r.width, r.height);
  }

  static Raster _resize(Raster r, BatchOptions o) {
    switch (o.resizeMode) {
      case ResizeMode.none:
        return r;
      case ResizeMode.maxSide:
        return Ops.fitWithin(r, o.maxSide);
      case ResizeMode.percent:
        final p = o.percent.clamp(1, 400) / 100;
        final w = (r.width * p).round().clamp(1, 20000), h = (r.height * p).round().clamp(1, 20000);
        return Ops.resize(r, w, h);
    }
  }

  static String outputName(String fileName, BatchOptions o) {
    final dot = fileName.lastIndexOf('.');
    final base = dot > 0 ? fileName.substring(0, dot) : fileName;
    return '$base${o.suffix}.${o.format.extension}';
  }
}
