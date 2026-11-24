import 'dart:typed_data';

import 'raster.dart';

/// 5x4 renk matrisi (satır öncelikli, Flutter `ColorFilter.matrix` ile aynı düzen).
///
/// R' = m0*R + m1*G + m2*B + m3*A + m4   (öteleme 0..255 aralığında)
/// G' = m5*R ...
///
/// Önizlemede GPU'da `ColorFilter.matrix` olarak, dışa aktarmada aynı
/// katsayılarla Dart'ta uygulanır; bu nedenle ekranda görülen sonuç ile
/// kaydedilen dosya aynı renk dönüşümünü alır.
class ColorMatrix {
  ColorMatrix(List<double> values) : values = List<double>.unmodifiable(values) {
    if (values.length != 20) throw ArgumentError('Renk matrisi 20 değer içermeli');
  }

  ColorMatrix.identity() : this(const [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0]);

  final List<double> values;

  bool get isIdentity {
    const id = [1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0, 0, 0, 0, 0, 1, 0];
    for (var i = 0; i < 20; i++) {
      if ((values[i] - id[i]).abs() > 1e-6) return false;
    }
    return true;
  }

  /// `other` önce, ardından `this` uygulanır: this ∘ other.
  ColorMatrix compose(ColorMatrix other) {
    final a = values;
    final b = other.values;
    final out = List<double>.filled(20, 0);
    for (var row = 0; row < 4; row++) {
      for (var col = 0; col < 5; col++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[row * 5 + k] * b[k * 5 + col];
        }
        if (col == 4) sum += a[row * 5 + 4];
        out[row * 5 + col] = sum;
      }
    }
    return ColorMatrix(out);
  }

  /// Birim matris ile bu matris arasında doğrusal geçiş (filtre yoğunluğu).
  ColorMatrix lerpFromIdentity(double t) {
    final id = ColorMatrix.identity().values;
    return ColorMatrix([for (var i = 0; i < 20; i++) id[i] + (values[i] - id[i]) * t]);
  }

  static ColorMatrix scale(double r, double g, double b) =>
      ColorMatrix([r, 0, 0, 0, 0, 0, g, 0, 0, 0, 0, 0, b, 0, 0, 0, 0, 0, 1, 0]);

  static ColorMatrix offset(double r, double g, double b) =>
      ColorMatrix([1, 0, 0, 0, r, 0, 1, 0, 0, g, 0, 0, 1, 0, b, 0, 0, 0, 1, 0]);

  /// Kontrast: orta gri (128) etrafında ölçekleme.
  static ColorMatrix contrast(double c) {
    final t = 128 * (1 - c);
    return ColorMatrix([c, 0, 0, 0, t, 0, c, 0, 0, t, 0, 0, c, 0, t, 0, 0, 0, 1, 0]);
  }

  /// Doygunluk (Rec.709 parlaklık katsayıları).
  static ColorMatrix saturation(double s) {
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    final sr = (1 - s) * lr, sg = (1 - s) * lg, sb = (1 - s) * lb;
    return ColorMatrix([
      sr + s, sg, sb, 0, 0, //
      sr, sg + s, sb, 0, 0, //
      sr, sg, sb + s, 0, 0, //
      0, 0, 0, 1, 0,
    ]);
  }

  static ColorMatrix grayscale() => saturation(0);

  static ColorMatrix sepia() => ColorMatrix(const [
        0.393, 0.769, 0.189, 0, 0, //
        0.349, 0.686, 0.168, 0, 0, //
        0.272, 0.534, 0.131, 0, 0, //
        0, 0, 0, 1, 0,
      ]);

  static ColorMatrix invert() => ColorMatrix(const [
        -1, 0, 0, 0, 255, //
        0, -1, 0, 0, 255, //
        0, 0, -1, 0, 255, //
        0, 0, 0, 1, 0,
      ]);

  /// Ham piksel tamponuna yerinde uygular.
  void applyTo(Raster raster) {
    if (isIdentity) return;
    final m = Float64List.fromList(values);
    final d = raster.rgba;
    // Alfa satırı birim ise (çoğu durumda) alfa hesaplanmaz.
    final alphaIdentity = m[15] == 0 && m[16] == 0 && m[17] == 0 && m[18] == 1 && m[19] == 0;
    for (var i = 0; i < d.length; i += 4) {
      final r = d[i].toDouble();
      final g = d[i + 1].toDouble();
      final b = d[i + 2].toDouble();
      final a = d[i + 3].toDouble();
      d[i] = clamp255(m[0] * r + m[1] * g + m[2] * b + m[3] * a + m[4]);
      d[i + 1] = clamp255(m[5] * r + m[6] * g + m[7] * b + m[8] * a + m[9]);
      d[i + 2] = clamp255(m[10] * r + m[11] * g + m[12] * b + m[13] * a + m[14]);
      if (!alphaIdentity) {
        d[i + 3] = clamp255(m[15] * r + m[16] * g + m[17] * b + m[18] * a + m[19]);
      }
    }
  }
}
