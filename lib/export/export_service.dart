import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

import '../editor/document.dart';
import '../image_engine/codec.dart';
import '../image_engine/engine.dart';
import '../image_engine/ops.dart';
import '../image_engine/raster.dart';
import '../layers/layer.dart';
import '../layers/layer_painter.dart';
import '../platform_services/ui_images.dart';
import '../projects/project_store.dart';

class ExportOptions {
  const ExportOptions({required this.format, required this.quality, required this.width, required this.height});

  final ExportFormat format;
  final int quality;
  final int width;
  final int height;
}

class ExportOutput {
  const ExportOutput(this.bytes, this.width, this.height, this.elapsed);
  final Uint8List bytes;
  final int width;
  final int height;
  final Duration elapsed;
}

/// Tam çözünürlüklü dışa aktarma.
///
/// 1) Taban görüntü arka plan isolate'inde işlenir (geometri, ayarlar).
/// 2) Katmanlar, önizlemeyle aynı [LayerPainter] koduyla GPU'da 2048 px'lik
///    karolar hâlinde çizilir (büyük görsellerde doku sınırına takılmaz).
/// 3) Sonuç isolate'te seçilen formata kodlanır.
class ExportService {
  ExportService._();

  static const int tileSize = 2048;

  static Future<ExportOutput> export({
    required ProjectStore store,
    required String projectId,
    required EditDocument doc,
    required ExportOptions options,
    void Function(String stage, double? fraction)? progress,
  }) async {
    final sw = Stopwatch()..start();
    progress?.call('Fotoğraf işleniyor…', null);
    final source = await store.readFile(projectId, doc.sourceFile);
    final base = await ImageEngine.renderFull(source, doc.sourceFile, doc.geometry, doc.adjustments,
        outWidth: options.width, outHeight: options.height);

    final visibleLayers = doc.layers.where((l) => l.visible).toList();
    if (visibleLayers.isNotEmpty) {
      progress?.call('Katmanlar birleştiriliyor…', 0);
      final images = await _loadFullAssets(store, projectId, visibleLayers);
      try {
        await compositeLayers(base, visibleLayers, images, doc.canvasWidth, doc.canvasHeight,
            progress: (f) => progress?.call('Katmanlar birleştiriliyor…', f));
      } finally {
        for (final img in images.values) {
          img.dispose();
        }
      }
    }
    progress?.call('${options.format.label} olarak kodlanıyor…', null);
    final bytes = await ImageEngine.encode(base, options.format, options.quality);
    sw.stop();
    return ExportOutput(bytes, base.width, base.height, sw.elapsed);
  }

  static Future<LayerImages> _loadFullAssets(ProjectStore store, String projectId, List<Layer> layers) async {
    final out = <String, ui.Image>{};
    for (final l in layers) {
      if (l is ImageLayer && !out.containsKey(l.assetFile)) {
        final bytes = await store.readAsset(projectId, l.assetFile);
        // Katman görseli, en fazla 4096 px (GPU doku sınırı ve bellek için).
        final load = await ImageEngine.loadPreview(bytes, l.assetFile, 4096);
        out[l.assetFile] = await UiImages.fromRaster(load.preview);
      }
    }
    return out;
  }

  /// [base] üzerine katmanları yerinde çizer. Belge koordinatları
  /// ([docWidth] x [docHeight]) çıktı boyutuna ölçeklenir.
  static Future<void> compositeLayers(
    Raster base,
    List<Layer> layers,
    LayerImages images,
    int docWidth,
    int docHeight, {
    void Function(double fraction)? progress,
  }) async {
    final sx = base.width / docWidth, sy = base.height / docHeight;
    final cols = (base.width / tileSize).ceil(), rows = (base.height / tileSize).ceil();
    final total = cols * rows;
    var done = 0;
    for (var ty = 0; ty < rows; ty++) {
      for (var tx = 0; tx < cols; tx++) {
        final x0 = tx * tileSize, y0 = ty * tileSize;
        final tw = math.min(tileSize, base.width - x0), th = math.min(tileSize, base.height - y0);
        final tileRaster = Ops.cropPixels(base, IntRect(x0, y0, tw, th));
        final tileImage = await UiImages.fromRaster(tileRaster);
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawImage(tileImage, Offset.zero, Paint());
        canvas.translate(-x0.toDouble(), -y0.toDouble());
        canvas.scale(sx, sy);
        LayerPainter.paintLayers(canvas, layers, images);
        final picture = recorder.endRecording();
        final out = await picture.toImage(tw, th);
        picture.dispose();
        tileImage.dispose();
        final result = await UiImages.toRaster(out);
        out.dispose();
        final rowBytes = tw * 4;
        for (var r = 0; r < th; r++) {
          final di = ((y0 + r) * base.width + x0) * 4;
          base.rgba.setRange(di, di + rowBytes, result.rgba, r * rowBytes);
        }
        done++;
        progress?.call(done / total);
      }
    }
  }
}
