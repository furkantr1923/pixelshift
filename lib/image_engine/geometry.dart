import 'dart:math' as math;

/// Normalize (0..1) dikdörtgen.
class NormRect {
  const NormRect(this.left, this.top, this.right, this.bottom);

  static const NormRect full = NormRect(0, 0, 1, 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;
  bool get isFull => left <= 0.0001 && top <= 0.0001 && right >= 0.9999 && bottom >= 0.9999;

  NormRect clampValid() {
    double c(double v) => v < 0 ? 0 : (v > 1 ? 1 : v);
    var l = c(left), t = c(top), r = c(right), b = c(bottom);
    if (r - l < 0.01) r = math.min(1.0, l + 0.01);
    if (b - t < 0.01) b = math.min(1.0, t + 0.01);
    return NormRect(l, t, r, b);
  }

  List<double> toJson() => [left, top, right, bottom];

  static NormRect fromJson(Object? json) {
    if (json is List && json.length == 4) {
      return NormRect(
        (json[0] as num).toDouble(),
        (json[1] as num).toDouble(),
        (json[2] as num).toDouble(),
        (json[3] as num).toDouble(),
      ).clampValid();
    }
    return full;
  }

  @override
  bool operator ==(Object other) =>
      other is NormRect && other.left == left && other.top == top && other.right == right && other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);
}

/// Geometrik dönüşümler. Uygulama sırası:
/// 1) 90° döndürme + yatay/dikey çevirme
/// 2) Düzleştirme (serbest açı, otomatik iç kırpma)
/// 3) Kırpma (düzleştirilmiş görüntüye göre normalize)
class Geometry {
  const Geometry({
    this.quarterTurns = 0,
    this.flipH = false,
    this.flipV = false,
    this.straighten = 0,
    this.crop = NormRect.full,
  });

  static const Geometry identity = Geometry();

  final int quarterTurns; // 0..3, saat yönünde
  final bool flipH;
  final bool flipV;
  final double straighten; // derece, -45..45, saat yönü pozitif
  final NormRect crop;

  bool get isIdentity => quarterTurns % 4 == 0 && !flipH && !flipV && straighten == 0 && crop.isFull;

  /// Kırpma dışındaki dönüşümler (kırpma modunda gösterilen görüntü).
  Geometry withoutCrop() => copyWith(crop: NormRect.full);

  /// Kaynak boyutundan çıktı boyutunu hesaplar.
  (int, int) outputSize(int srcW, int srcH) {
    var (w, h) = orientedSize(srcW, srcH);
    final (sw, sh) = straightenedSize(w, h, straighten);
    w = sw;
    h = sh;
    final cw = math.max(1, (crop.width * w).round());
    final ch = math.max(1, (crop.height * h).round());
    return (cw, ch);
  }

  (int, int) orientedSize(int srcW, int srcH) => quarterTurns.isOdd ? (srcH, srcW) : (srcW, srcH);

  /// Düzleştirme sonrası iç dikdörtgenin boyutu (aynı en-boy oranı).
  static (int, int) straightenedSize(int w, int h, double degrees) {
    if (degrees == 0) return (w, h);
    final s = straightenScale(w, h, degrees);
    return (math.max(1, (w * s).floor()), math.max(1, (h * s).floor()));
  }

  static double straightenScale(int w, int h, double degrees) {
    final a = degrees.abs() * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    return math.min(w / (w * c + h * s), h / (w * s + h * c));
  }

  Geometry copyWith({int? quarterTurns, bool? flipH, bool? flipV, double? straighten, NormRect? crop}) {
    return Geometry(
      quarterTurns: (quarterTurns ?? this.quarterTurns) % 4,
      flipH: flipH ?? this.flipH,
      flipV: flipV ?? this.flipV,
      straighten: straighten ?? this.straighten,
      crop: crop ?? this.crop,
    );
  }

  Map<String, Object?> toJson() => {
        'quarterTurns': quarterTurns,
        'flipH': flipH,
        'flipV': flipV,
        'straighten': straighten,
        'crop': crop.toJson(),
      };

  factory Geometry.fromJson(Map<String, Object?> json) => Geometry(
        quarterTurns: ((json['quarterTurns'] as num?)?.toInt() ?? 0) % 4,
        flipH: json['flipH'] == true,
        flipV: json['flipV'] == true,
        straighten: (json['straighten'] as num?)?.toDouble() ?? 0,
        crop: NormRect.fromJson(json['crop']),
      );

  @override
  bool operator ==(Object other) =>
      other is Geometry &&
      other.quarterTurns == quarterTurns &&
      other.flipH == flipH &&
      other.flipV == flipV &&
      other.straighten == straighten &&
      other.crop == crop;

  @override
  int get hashCode => Object.hash(quarterTurns, flipH, flipV, straighten, crop);
}
