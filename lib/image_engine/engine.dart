import 'dart:isolate';
import 'dart:math' as math;
import 'dart:typed_data';

import '../filters/adjustments.dart';
import 'codec.dart';
import 'geometry.dart';
import 'ops.dart';
import 'raster.dart';

/// İçe aktarma sonucu.
class ImportedImage {
  const ImportedImage({
    required this.storedBytes,
    required this.storedExtension,
    required this.width,
    required this.height,
    required this.preview,
    required this.kind,
    this.note,
  });

  /// Proje klasörüne yazılacak kaynak (orijinal bayt veya dönüştürülmüş PNG).
  final Uint8List storedBytes;
  final String storedExtension;
  final int width;
  final int height;
  final Raster preview;
  final ImageKind kind;
  final String? note;
}

class PreviewLoad {
  const PreviewLoad({required this.preview, required this.fullWidth, required this.fullHeight});
  final Raster preview;
  final int fullWidth;
  final int fullHeight;
}

/// Ağır işlemleri arka plan isolate'lerinde çalıştıran giriş noktaları.
///
/// Tüm fonksiyonlar statiktir ve yalnızca gönderilebilir (sendable) verileri
/// yakalar; arayüz iş parçacığı hiçbir zaman donmaz.
class ImageEngine {
  ImageEngine._();

  /// Bu boyutun üstündeki görseller için kullanıcı uyarılır (megapiksel).
  static const int largeImageMegapixels = 40;

  /// Kod çözmeden önce güvenlik sınırı (megapiksel).
  static const int maxMegapixels = 200;

  // ------------------------------------------------------------ İçe aktarma

  static Future<ImportedImage> importImage(Uint8List bytes, String fileName, int previewMaxSide) {
    return Isolate.run(() => importImageSync(bytes, fileName, previewMaxSide));
  }

  static ImportedImage importImageSync(Uint8List bytes, String fileName, int previewMaxSide) {
    final kind = ImageCodec.detect(bytes, fileName);
    if (kind == ImageKind.jpeg) {
      // Orijinal saklanır; yalnızca ölçekli önizleme çözülür (hızlı içe aktarma).
      final (preview, w, h) = ImageCodec.decodePreview(bytes, fileName, previewMaxSide);
      return ImportedImage(
        storedBytes: bytes,
        storedExtension: 'jpg',
        width: w,
        height: h,
        preview: preview,
        kind: kind,
      );
    }
    final full = ImageCodec.decode(bytes, fileName);
    _checkSize(full);
    final keepOriginal = kind == ImageKind.jpeg ||
        kind == ImageKind.png ||
        kind == ImageKind.webp ||
        kind == ImageKind.bmp ||
        kind == ImageKind.tiff ||
        kind == ImageKind.gif;
    final stored = keepOriginal ? bytes : ImageCodec.encode(full, ExportFormat.png);
    final ext = keepOriginal ? _extFor(kind) : 'png';
    return ImportedImage(
      storedBytes: stored,
      storedExtension: ext,
      width: full.width,
      height: full.height,
      preview: Ops.fitWithin(full, previewMaxSide),
      kind: kind,
      note: ImageCodec.limitationNote(kind),
    );
  }

  /// Zaten çözülmüş (ör. SVG'den rasterleştirilmiş) pikselleri içe aktarır.
  static Future<ImportedImage> importRaster(Raster raster, ImageKind kind, int previewMaxSide) {
    return Isolate.run(() {
      return ImportedImage(
        storedBytes: ImageCodec.encode(raster, ExportFormat.png),
        storedExtension: 'png',
        width: raster.width,
        height: raster.height,
        preview: Ops.fitWithin(raster, previewMaxSide),
        kind: kind,
        note: ImageCodec.limitationNote(kind),
      );
    });
  }

  static String _extFor(ImageKind k) => switch (k) {
        ImageKind.jpeg => 'jpg',
        ImageKind.png => 'png',
        ImageKind.webp => 'webp',
        ImageKind.bmp => 'bmp',
        ImageKind.tiff => 'tiff',
        ImageKind.gif => 'gif',
        _ => 'png',
      };

  static void _checkSize(Raster r) {
    if (r.pixelCount > maxMegapixels * 1000000) {
      throw ArgumentError('Görsel çok büyük (${r.width}x${r.height}).');
    }
  }

  /// Kayıtlı bir projenin kaynağını önizleme boyutunda yükler.
  static Future<PreviewLoad> loadPreview(Uint8List bytes, String fileName, int maxSide) {
    return Isolate.run(() {
      final (preview, w, h) = ImageCodec.decodePreview(bytes, fileName, maxSide);
      return PreviewLoad(preview: preview, fullWidth: w, fullHeight: h);
    });
  }

  // ------------------------------------------------------------ İşleme hattı

  /// Detay/ton ayarları (komşuluk gerektirenler). Sıra sabittir:
  /// gölge/açık ton → netlik → keskinlik → bulanıklık → vinyet → grenlenme.
  static Raster applyDetail(Raster input, Adjustments a) {
    if (!a.hasDetailOps) return input;
    var r = input.clone();
    Ops.shadowsHighlightsInPlace(r, a.shadows, a.highlights);
    if (a.clarity != 0) {
      r = Ops.unsharp(r, radius: Ops.scaledRadius(r, 14), amount: a.clarity / 100 * 0.7);
    }
    if (a.sharpness != 0) {
      r = Ops.unsharp(r, radius: Ops.scaledRadius(r, 0.9), amount: a.sharpness / 100 * 1.6, threshold: 2);
    }
    if (a.blur > 0) {
      r = Ops.boxBlur(r, Ops.scaledRadius(r, a.blur / 100 * 10));
    }
    Ops.vignetteInPlace(r, a.effectiveVignette);
    Ops.grainInPlace(r, a.effectiveGrain, seed: 7919);
    return r;
  }

  /// Önizleme: geometri + detay. Renk matrisi GPU'da uygulanır.
  static Future<Raster> renderPreview(Raster source, Geometry geometry, Adjustments adjustments) {
    return Isolate.run(() {
      final geo = Ops.applyGeometry(source, geometry);
      return applyDetail(geo, adjustments);
    });
  }

  /// Tam çözünürlüklü taban görüntü (katmanlar hariç):
  /// çöz → geometri → (isteğe bağlı) boyutlandır → detay → renk.
  static Future<Raster> renderFull(
    Uint8List sourceBytes,
    String sourceName,
    Geometry geometry,
    Adjustments adjustments, {
    int? outWidth,
    int? outHeight,
  }) {
    return Isolate.run(() => renderFullSync(sourceBytes, sourceName, geometry, adjustments,
        outWidth: outWidth, outHeight: outHeight));
  }

  static Raster renderFullSync(
    Uint8List sourceBytes,
    String sourceName,
    Geometry geometry,
    Adjustments adjustments, {
    int? outWidth,
    int? outHeight,
  }) {
    var r = ImageCodec.decode(sourceBytes, sourceName);
    r = Ops.applyGeometry(r, geometry);
    if (outWidth != null && outHeight != null && (outWidth != r.width || outHeight != r.height)) {
      r = Ops.resize(r, math.max(1, outWidth), math.max(1, outHeight));
    }
    r = applyDetail(r, adjustments);
    adjustments.colorMatrix().applyTo(r);
    return r;
  }

  /// Kodlama (isolate). JPG/BMP için şeffaflık beyaza birleştirilir.
  static Future<Uint8List> encode(Raster raster, ExportFormat format, int quality) {
    return Isolate.run(() => encodeSync(raster, format, quality));
  }

  static Uint8List encodeSync(Raster raster, ExportFormat format, int quality) {
    var r = raster;
    if (!format.supportsTransparency && r.hasTransparency) {
      r = r.clone();
      Ops.flattenInPlace(r);
    }
    return ImageCodec.encode(r, format, quality: quality);
  }

  /// Küçük önizleme (ör. proje kartı, filtre küçük resimleri).
  static Future<Raster> thumbnail(Raster source, int maxSide) => Isolate.run(() => Ops.fitWithin(source, maxSide));

  /// Düz renk veya geçişli boş tuval (şablon/kolaj tabanı) — PNG baytları.
  static Future<Uint8List> blankCanvasPng(int width, int height, int topArgb, int bottomArgb) {
    return Isolate.run(() {
      final r = topArgb == bottomArgb
          ? Raster.filled(width, height, (topArgb >> 16) & 255, (topArgb >> 8) & 255, topArgb & 255, (topArgb >> 24) & 255)
          : Ops.gradient(width, height, topArgb, bottomArgb);
      return ImageCodec.encode(r, ExportFormat.png);
    });
  }
}
