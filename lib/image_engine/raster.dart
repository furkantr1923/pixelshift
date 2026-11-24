import 'dart:math' as math;
import 'dart:typed_data';

/// PIXELSHIFT görüntü motorunun temel veri yapısı.
///
/// Düz (premultiplied olmayan) RGBA, 8 bit/kanal, satır öncelikli piksel
/// tamponu. Isolate'ler arasında [Uint8List] olarak taşınabilir ve hem
/// önizleme hem de tam çözünürlüklü dışa aktarma aynı fonksiyonlarla işlenir.
class Raster {
  Raster(this.width, this.height, [Uint8List? rgba])
      : rgba = rgba ?? Uint8List(width * height * 4) {
    if (width <= 0 || height <= 0) {
      throw ArgumentError('Geçersiz görüntü boyutu: ${width}x$height');
    }
    if (this.rgba.length != width * height * 4) {
      throw ArgumentError('Piksel tamponu boyutu uyuşmuyor');
    }
  }

  /// Tek renkle doldurulmuş tuval.
  factory Raster.filled(int width, int height, int r, int g, int b, [int a = 255]) {
    final raster = Raster(width, height);
    final data = raster.rgba;
    for (var i = 0; i < data.length; i += 4) {
      data[i] = r;
      data[i + 1] = g;
      data[i + 2] = b;
      data[i + 3] = a;
    }
    return raster;
  }

  final int width;
  final int height;
  final Uint8List rgba;

  int get pixelCount => width * height;
  int get longSide => math.max(width, height);

  Raster clone() => Raster(width, height, Uint8List.fromList(rgba));

  /// Herhangi bir pikselde tam opak olmayan alfa var mı?
  bool get hasTransparency {
    for (var i = 3; i < rgba.length; i += 4) {
      if (rgba[i] != 255) return true;
    }
    return false;
  }

  /// Bellek tahmini (bayt).
  int get byteSize => rgba.length;
}

int clamp255(num v) {
  if (v <= 0) return 0;
  if (v >= 255) return 255;
  return v.round();
}

double clamp01(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);

/// Sınırlandırılmış dikdörtgen (piksel).
class IntRect {
  const IntRect(this.x, this.y, this.width, this.height);
  final int x;
  final int y;
  final int width;
  final int height;

  @override
  String toString() => 'IntRect($x, $y, $width, $height)';
}
