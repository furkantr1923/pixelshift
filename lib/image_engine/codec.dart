import 'dart:typed_data';

import 'package:image/image.dart' as img;

import '../core/errors.dart';
import 'ops.dart';
import 'raster.dart';
import 'webp_encoder.dart';

/// Desteklenen dosya türleri ve gerçek yetenekleri.
enum ImageKind { jpeg, png, webp, bmp, tiff, gif, psd, raw, svg, heic, unknown }

enum ExportFormat { jpg, png, webp, bmp, tiff }

extension ExportFormatInfo on ExportFormat {
  String get extension => switch (this) {
        ExportFormat.jpg => 'jpg',
        ExportFormat.png => 'png',
        ExportFormat.webp => 'webp',
        ExportFormat.bmp => 'bmp',
        ExportFormat.tiff => 'tiff',
      };

  String get label => switch (this) {
        ExportFormat.jpg => 'JPG',
        ExportFormat.png => 'PNG',
        ExportFormat.webp => 'WEBP',
        ExportFormat.bmp => 'BMP',
        ExportFormat.tiff => 'TIFF',
      };

  String get mimeType => switch (this) {
        ExportFormat.jpg => 'image/jpeg',
        ExportFormat.png => 'image/png',
        ExportFormat.webp => 'image/webp',
        ExportFormat.bmp => 'image/bmp',
        ExportFormat.tiff => 'image/tiff',
      };

  bool get supportsTransparency => this == ExportFormat.png || this == ExportFormat.webp || this == ExportFormat.tiff;

  bool get supportsQuality => this == ExportFormat.jpg || this == ExportFormat.webp;

  static ExportFormat fromName(String? name) {
    for (final f in ExportFormat.values) {
      if (f.name == name) return f;
    }
    return ExportFormat.jpg;
  }
}

class ImageCodec {
  ImageCodec._();

  static const rawExtensions = {
    'cr2', 'cr3', 'crw', 'nef', 'nrw', 'arw', 'srf', 'sr2', 'dng', 'orf', 'rw2', 'raf', 'pef', 'srw', 'raw', 'rwl', '3fr', 'erf', 'kdc', 'mrw', 'x3f', //
  };

  /// Dosya seçicilerde gösterilen uzantılar.
  static const openExtensions = [
    'jpg', 'jpeg', 'jpe', 'jfif', 'png', 'webp', 'bmp', 'dib', 'tif', 'tiff', 'gif', 'psd', 'svg', //
    'cr2', 'cr3', 'nef', 'nrw', 'arw', 'dng', 'orf', 'rw2', 'raf', 'pef', 'srw', 'raw',
  ];

  static String extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1).toLowerCase();
  }

  /// Sihirli baytlar + uzantı ile tür tespiti (uzantıya körü körüne güvenilmez).
  static ImageKind detect(Uint8List b, String fileName) {
    final ext = extensionOf(fileName);
    bool at(int offset, List<int> sig) {
      if (b.length < offset + sig.length) return false;
      for (var i = 0; i < sig.length; i++) {
        if (b[offset + i] != sig[i]) return false;
      }
      return true;
    }

    if (rawExtensions.contains(ext)) {
      // RAW dosyalarının çoğu TIFF tabanlıdır; uzantı burada belirleyicidir.
      if (at(0, [0x49, 0x49]) || at(0, [0x4d, 0x4d]) || at(4, [0x66, 0x74, 0x79, 0x70]) || at(0, 'FUJIFILM'.codeUnits)) {
        return ImageKind.raw;
      }
    }
    if (at(0, [0xff, 0xd8, 0xff])) return ImageKind.jpeg;
    if (at(0, [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a])) return ImageKind.png;
    if (at(0, 'RIFF'.codeUnits) && at(8, 'WEBP'.codeUnits)) return ImageKind.webp;
    if (at(0, 'GIF87a'.codeUnits) || at(0, 'GIF89a'.codeUnits)) return ImageKind.gif;
    if (at(0, 'BM'.codeUnits) && b.length > 26) return ImageKind.bmp;
    if (at(0, '8BPS'.codeUnits)) return ImageKind.psd;
    if (at(0, [0x49, 0x49, 0x2a, 0x00]) || at(0, [0x4d, 0x4d, 0x00, 0x2a])) return ImageKind.tiff;
    if (at(4, 'ftyp'.codeUnits)) {
      final brand = b.length >= 12 ? String.fromCharCodes(b.sublist(8, 12)) : '';
      if (brand.startsWith('crx')) return ImageKind.raw;
      if (brand.startsWith('hei') || brand.startsWith('mif') || brand.startsWith('hev') || brand.startsWith('avi')) {
        return ImageKind.heic;
      }
    }
    if (ext == 'svg' || _looksLikeSvg(b)) return ImageKind.svg;
    return ImageKind.unknown;
  }

  static bool _looksLikeSvg(Uint8List b) {
    final n = b.length < 1024 ? b.length : 1024;
    final head = String.fromCharCodes(b.sublist(0, n)).toLowerCase();
    return head.contains('<svg');
  }

  static String kindLabel(ImageKind k) => switch (k) {
        ImageKind.jpeg => 'JPEG',
        ImageKind.png => 'PNG',
        ImageKind.webp => 'WEBP',
        ImageKind.bmp => 'BMP',
        ImageKind.tiff => 'TIFF',
        ImageKind.gif => 'GIF',
        ImageKind.psd => 'PSD',
        ImageKind.raw => 'RAW',
        ImageKind.svg => 'SVG',
        ImageKind.heic => 'HEIC/AVIF',
        ImageKind.unknown => 'Bilinmeyen',
      };

  /// Kullanıcıya gösterilecek, formatın sınırlamasını anlatan not (varsa).
  static String? limitationNote(ImageKind k) => switch (k) {
        ImageKind.gif => 'GIF animasyonu korunmaz: yalnızca ilk kare düzenlenir.',
        ImageKind.psd => 'PSD: Photoshop katmanları ayrı ayrı açılmaz; birleştirilmiş görüntü düzenlenir.',
        ImageKind.raw =>
          'RAW: Ham sensör verisi işlenmez; kameranın dosyaya gömdüğü JPEG önizlemesi kullanılır (çözünürlük kameraya göre değişir).',
        ImageKind.svg => 'SVG: Vektör çizim piksel görüntüye dönüştürülerek düzenlenir.',
        _ => null,
      };

  /// Bayt dizisini [Raster]'a çözer. SVG bu katmanda çözülmez
  /// (Flutter gerektirir; bkz. platform_services/svg_rasterizer.dart).
  /// EXIF yönü uygulanır, meta veriler atılır.
  static Raster decode(Uint8List bytes, String fileName) {
    if (bytes.isEmpty) throw const UserFacingException('Dosya boş.');
    final kind = detect(bytes, fileName);
    img.Image? image;
    try {
      switch (kind) {
        case ImageKind.jpeg:
          image = img.decodeJpg(bytes);
        case ImageKind.png:
          image = img.decodePng(bytes);
        case ImageKind.webp:
          image = img.decodeWebP(bytes);
        case ImageKind.gif:
          image = img.decodeGif(bytes);
        case ImageKind.bmp:
          image = img.decodeBmp(bytes);
        case ImageKind.tiff:
          image = img.decodeTiff(bytes);
        case ImageKind.psd:
          image = img.decodePsd(bytes);
        case ImageKind.raw:
          return _decodeRawPreview(bytes);
        case ImageKind.svg:
          throw const UserFacingException('SVG dosyası bu aşamada çözülemez.');
        case ImageKind.heic:
          throw const UserFacingException(
              'HEIC/AVIF formatı desteklenmiyor. Fotoğrafı telefonunuzda JPG olarak dışa aktarıp tekrar deneyin.');
        case ImageKind.unknown:
          throw const UserFacingException(
              'Bu dosya desteklenen bir görüntü formatında değil. Desteklenenler: JPG, PNG, WEBP, BMP, TIFF, GIF, PSD, SVG, RAW.');
      }
    } on UserFacingException {
      rethrow;
    } catch (_) {
      image = null;
    }
    if (image == null) {
      throw UserFacingException(
          '${kindLabel(kind)} dosyası okunamadı. Dosya bozuk olabilir ya da bu ${kindLabel(kind)} türevi desteklenmiyor.');
    }
    if (kind == ImageKind.jpeg || kind == ImageKind.tiff || kind == ImageKind.webp || kind == ImageKind.png) {
      image = img.bakeOrientation(image);
    }
    return fromImage(image);
  }

  /// Önizleme için hızlı çözme: JPEG'de DCT ölçekli çözme (1/2, 1/4, 1/8)
  /// kullanılır; tam çözünürlük belleğe alınmaz. Tam (yönlendirilmiş) boyutu döndürür.
  static (Raster, int, int) decodePreview(Uint8List bytes, String fileName, int maxSide) {
    if (detect(bytes, fileName) == ImageKind.jpeg) {
      try {
        final info = img.JpegDecoder().startDecode(bytes);
        if (info != null && info.width > 0 && info.height > 0) {
          final longSide = info.width > info.height ? info.width : info.height;
          var scale = 1;
          while (scale < 8 && longSide / (scale * 2) >= maxSide) {
            scale *= 2;
          }
          final decoded = img.decodeJpg(bytes, scale: scale);
          if (decoded != null) {
            final orientation = decoded.exif.imageIfd.orientation ?? 1;
            final swap = orientation >= 5 && orientation <= 8;
            final preview = fromImage(img.bakeOrientation(decoded));
            final fw = swap ? info.height : info.width;
            final fh = swap ? info.width : info.height;
            return (_fit(preview, maxSide), fw, fh);
          }
        }
      } catch (_) {
        // Hızlı yol başarısızsa tam çözmeye düş.
      }
    }
    final full = decode(bytes, fileName);
    return (_fit(full, maxSide), full.width, full.height);
  }

  static Raster _fit(Raster r, int maxSide) => Ops.fitWithin(r, maxSide);

  /// `image` paketi görüntüsünü 8 bit RGBA [Raster]'a çevirir.
  static Raster fromImage(img.Image image) {
    var src = image;
    if (src.hasPalette || src.format != img.Format.uint8 || src.numChannels != 4) {
      src = src.convert(format: img.Format.uint8, numChannels: 4, alpha: 255);
    }
    final bytes = src.getBytes(order: img.ChannelOrder.rgba);
    // Hizalı, kendine ait bir kopya (Uint32 görünümleri için gerekli).
    return Raster(src.width, src.height, Uint8List.fromList(bytes));
  }

  static img.Image toImage(Raster r) {
    return img.Image.fromBytes(
      width: r.width,
      height: r.height,
      bytes: Uint8List.fromList(r.rgba).buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
  }

  /// RAW: dosyadaki en büyük gömülü JPEG önizlemeyi bulur.
  static Raster _decodeRawPreview(Uint8List bytes) {
    img.Image? best;
    var tried = 0;
    for (var i = 0; i + 3 < bytes.length && tried < 12; i++) {
      if (bytes[i] == 0xff && bytes[i + 1] == 0xd8 && bytes[i + 2] == 0xff) {
        // SOI sonrası işaretçi geçerli bir JPEG işaretçisi olmalı.
        final marker = bytes[i + 3];
        if (marker < 0xc0) continue;
        tried++;
        try {
          final candidate = img.decodeJpg(Uint8List.sublistView(bytes, i));
          if (candidate != null &&
              (best == null || candidate.width * candidate.height > best.width * best.height)) {
            best = candidate;
          }
        } catch (_) {
          // geçersiz aday, devam
        }
      }
    }
    if (best == null || best.width < 64) {
      throw const UserFacingException(
          'Bu RAW dosyasında kullanılabilir gömülü önizleme bulunamadı. Ham sensör verisi işleme desteklenmiyor; '
          'dosyayı kamera yazılımıyla JPG/TIFF olarak dışa aktarın.');
    }
    return fromImage(img.bakeOrientation(best));
  }

  /// Dışa aktarma. JPG ve BMP şeffaflık desteklemediği için
  /// çağıran taraf önce beyaz zemine birleştirmelidir.
  static Uint8List encode(Raster r, ExportFormat format, {int quality = 92}) {
    switch (format) {
      case ExportFormat.jpg:
        return Uint8List.fromList(img.encodeJpg(_rgbImage(r), quality: quality.clamp(1, 100)));
      case ExportFormat.png:
        return Uint8List.fromList(img.encodePng(toImage(r), level: 6));
      case ExportFormat.webp:
        // 100: PIXELSHIFT'in kendi kayıpsız VP8L kodlayıcısı; altı: kayıplı VP8.
        if (quality >= 100) return WebpEncoder.encode(r);
        return Uint8List.fromList(img.encodeWebP(toImage(r), lossless: false, quality: quality.clamp(1, 99), method: 4));
      case ExportFormat.bmp:
        return Uint8List.fromList(img.encodeBmp(_rgbImage(r)));
      case ExportFormat.tiff:
        return Uint8List.fromList(img.encodeTiff(toImage(r)));
    }
  }

  static img.Image _rgbImage(Raster r) {
    final rgb = Uint8List(r.pixelCount * 3);
    final s = r.rgba;
    for (var i = 0, j = 0; i < s.length; i += 4, j += 3) {
      rgb[j] = s[i];
      rgb[j + 1] = s[i + 1];
      rgb[j + 2] = s[i + 2];
    }
    return img.Image.fromBytes(width: r.width, height: r.height, bytes: rgb.buffer, numChannels: 3);
  }
}
