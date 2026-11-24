import 'dart:math' as math;

import '../image_engine/color_matrix.dart';
import 'filter_presets.dart';

/// Fotoğrafa uygulanan tahribatsız ayarlar.
///
/// Tüm değerler -100..100 (veya 0..100) aralığında kullanıcı birimidir.
/// İki gruba ayrılır:
/// - Renk ayarları: tek bir [ColorMatrix]'e indirgenir (önizlemede GPU'da anında).
/// - Detay/ton ayarları: komşu piksellere veya parlaklığa bağlıdır, arka plan
///   isolate'inde işlenir (keskinlik, netlik, gölgeler, vinyet, grenlenme...).
class Adjustments {
  const Adjustments({
    this.exposure = 0,
    this.brightness = 0,
    this.contrast = 0,
    this.saturation = 0,
    this.temperature = 0,
    this.tint = 0,
    this.grayscale = false,
    this.shadows = 0,
    this.highlights = 0,
    this.sharpness = 0,
    this.clarity = 0,
    this.blur = 0,
    this.vignette = 0,
    this.grain = 0,
    this.filterId = 'none',
    this.filterIntensity = 100,
  });

  final double exposure; // -100..100
  final double brightness; // -100..100
  final double contrast; // -100..100
  final double saturation; // -100..100
  final double temperature; // -100..100 (soğuk..sıcak)
  final double tint; // -100..100 (yeşil..macenta)
  final bool grayscale;
  final double shadows; // -100..100
  final double highlights; // -100..100
  final double sharpness; // 0..100
  final double clarity; // 0..100
  final double blur; // 0..100
  final double vignette; // -100..100 (negatif: kararan kenarlar)
  final double grain; // 0..100
  final String filterId;
  final double filterIntensity; // 0..100

  static const Adjustments none = Adjustments();

  bool get isNeutral => this == none;

  FilterPreset get filter => FilterPresets.byId(filterId);

  /// Renk ayarlarının ve seçili filtrenin birleşik matrisi.
  ColorMatrix colorMatrix() {
    var m = ColorMatrix.identity();
    if (exposure != 0) {
      final gain = math.pow(2, exposure / 50).toDouble(); // ±2 EV
      m = ColorMatrix.scale(gain, gain, gain).compose(m);
    }
    if (brightness != 0) {
      final o = brightness / 100 * 90;
      m = ColorMatrix.offset(o, o, o).compose(m);
    }
    if (contrast != 0) {
      final c = contrast >= 0 ? 1 + contrast / 100 * 1.2 : 1 + contrast / 100 * 0.85;
      m = ColorMatrix.contrast(c).compose(m);
    }
    if (temperature != 0 || tint != 0) {
      final t = temperature / 100;
      final n = tint / 100;
      m = ColorMatrix.scale(1 + 0.22 * t + 0.06 * n, 1 - 0.14 * n, 1 - 0.22 * t + 0.06 * n).compose(m);
    }
    if (saturation != 0) {
      final s = saturation >= 0 ? 1 + saturation / 100 * 1.0 : 1 + saturation / 100;
      m = ColorMatrix.saturation(s).compose(m);
    }
    if (grayscale) {
      m = ColorMatrix.grayscale().compose(m);
    }
    final preset = filter;
    if (preset.matrix != null && filterIntensity > 0) {
      m = preset.matrix!.lerpFromIdentity(filterIntensity / 100).compose(m);
    }
    return m;
  }

  /// Filtrenin katkısı dahil, isolate'te uygulanacak vinyet miktarı.
  double get effectiveVignette {
    final f = filter.vignette * filterIntensity / 100;
    return (vignette + f).clamp(-100, 100).toDouble();
  }

  double get effectiveGrain {
    final f = filter.grain * filterIntensity / 100;
    return (grain + f).clamp(0, 100).toDouble();
  }

  /// İsolate gerektiren (komşuluk/ton) ayar var mı?
  bool get hasDetailOps =>
      shadows != 0 ||
      highlights != 0 ||
      sharpness != 0 ||
      clarity != 0 ||
      blur != 0 ||
      effectiveVignette != 0 ||
      effectiveGrain != 0;

  Adjustments copyWith({
    double? exposure,
    double? brightness,
    double? contrast,
    double? saturation,
    double? temperature,
    double? tint,
    bool? grayscale,
    double? shadows,
    double? highlights,
    double? sharpness,
    double? clarity,
    double? blur,
    double? vignette,
    double? grain,
    String? filterId,
    double? filterIntensity,
  }) {
    return Adjustments(
      exposure: exposure ?? this.exposure,
      brightness: brightness ?? this.brightness,
      contrast: contrast ?? this.contrast,
      saturation: saturation ?? this.saturation,
      temperature: temperature ?? this.temperature,
      tint: tint ?? this.tint,
      grayscale: grayscale ?? this.grayscale,
      shadows: shadows ?? this.shadows,
      highlights: highlights ?? this.highlights,
      sharpness: sharpness ?? this.sharpness,
      clarity: clarity ?? this.clarity,
      blur: blur ?? this.blur,
      vignette: vignette ?? this.vignette,
      grain: grain ?? this.grain,
      filterId: filterId ?? this.filterId,
      filterIntensity: filterIntensity ?? this.filterIntensity,
    );
  }

  Map<String, Object?> toJson() => {
        'exposure': exposure,
        'brightness': brightness,
        'contrast': contrast,
        'saturation': saturation,
        'temperature': temperature,
        'tint': tint,
        'grayscale': grayscale,
        'shadows': shadows,
        'highlights': highlights,
        'sharpness': sharpness,
        'clarity': clarity,
        'blur': blur,
        'vignette': vignette,
        'grain': grain,
        'filterId': filterId,
        'filterIntensity': filterIntensity,
      };

  factory Adjustments.fromJson(Map<String, Object?> json) {
    double d(String key, [double fallback = 0]) {
      final v = json[key];
      return v is num ? v.toDouble() : fallback;
    }

    return Adjustments(
      exposure: d('exposure'),
      brightness: d('brightness'),
      contrast: d('contrast'),
      saturation: d('saturation'),
      temperature: d('temperature'),
      tint: d('tint'),
      grayscale: json['grayscale'] == true,
      shadows: d('shadows'),
      highlights: d('highlights'),
      sharpness: d('sharpness'),
      clarity: d('clarity'),
      blur: d('blur'),
      vignette: d('vignette'),
      grain: d('grain'),
      filterId: json['filterId'] is String ? json['filterId']! as String : 'none',
      filterIntensity: d('filterIntensity', 100),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is Adjustments &&
        other.exposure == exposure &&
        other.brightness == brightness &&
        other.contrast == contrast &&
        other.saturation == saturation &&
        other.temperature == temperature &&
        other.tint == tint &&
        other.grayscale == grayscale &&
        other.shadows == shadows &&
        other.highlights == highlights &&
        other.sharpness == sharpness &&
        other.clarity == clarity &&
        other.blur == blur &&
        other.vignette == vignette &&
        other.grain == grain &&
        other.filterId == filterId &&
        other.filterIntensity == filterIntensity;
  }

  @override
  int get hashCode => Object.hashAll([
        exposure,
        brightness,
        contrast,
        saturation,
        temperature,
        tint,
        grayscale,
        shadows,
        highlights,
        sharpness,
        clarity,
        blur,
        vignette,
        grain,
        filterId,
        filterIntensity,
      ]);
}
