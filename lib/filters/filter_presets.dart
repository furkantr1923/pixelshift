import '../image_engine/color_matrix.dart';

/// Hazır renk filtresi.
///
/// Her filtre bir renk matrisi ve isteğe bağlı vinyet/grenlenme katkısından
/// oluşur. Yoğunluk kaydırıcısı matrisi birim matrisle harmanlar.
class FilterPreset {
  const FilterPreset({
    required this.id,
    required this.name,
    this.matrix,
    this.vignette = 0,
    this.grain = 0,
  });

  final String id;
  final String name;
  final ColorMatrix? matrix;
  final double vignette;
  final double grain;
}

class FilterPresets {
  FilterPresets._();

  static ColorMatrix _m(List<double> v) => ColorMatrix(v);

  static ColorMatrix _chain(List<ColorMatrix> steps) {
    var m = ColorMatrix.identity();
    for (final s in steps) {
      m = s.compose(m);
    }
    return m;
  }

  static final List<FilterPreset> all = [
    const FilterPreset(id: 'none', name: 'Orijinal'),
    FilterPreset(id: 'bw', name: 'Siyah-Beyaz', matrix: ColorMatrix.grayscale()),
    FilterPreset(
      id: 'noir',
      name: 'Noir',
      matrix: _chain([ColorMatrix.grayscale(), ColorMatrix.contrast(1.45), ColorMatrix.offset(-12, -12, -12)]),
      vignette: -35,
    ),
    FilterPreset(id: 'sepia', name: 'Sepya', matrix: ColorMatrix.sepia()),
    FilterPreset(
      id: 'vintage',
      name: 'Vintage',
      matrix: _chain([
        ColorMatrix.saturation(0.7),
        ColorMatrix.scale(1.06, 0.98, 0.86),
        ColorMatrix.contrast(0.88),
        ColorMatrix.offset(14, 8, 0),
      ]),
      vignette: -25,
      grain: 12,
    ),
    FilterPreset(
      id: 'film',
      name: 'Film',
      matrix: _chain([
        ColorMatrix.contrast(1.08),
        ColorMatrix.scale(1.03, 1.0, 0.94),
        ColorMatrix.offset(6, 4, 10),
        ColorMatrix.saturation(0.92),
      ]),
      grain: 18,
    ),
    FilterPreset(
      id: 'warm',
      name: 'Sıcak',
      matrix: _chain([ColorMatrix.scale(1.10, 1.02, 0.86), ColorMatrix.saturation(1.08)]),
    ),
    FilterPreset(
      id: 'cool',
      name: 'Soğuk',
      matrix: _chain([ColorMatrix.scale(0.90, 1.0, 1.12), ColorMatrix.offset(0, 2, 6)]),
    ),
    FilterPreset(
      id: 'vivid',
      name: 'Canlı',
      matrix: _chain([ColorMatrix.saturation(1.45), ColorMatrix.contrast(1.12)]),
    ),
    FilterPreset(
      id: 'fade',
      name: 'Soluk',
      matrix: _chain([ColorMatrix.contrast(0.78), ColorMatrix.offset(18, 18, 18), ColorMatrix.saturation(0.8)]),
    ),
    FilterPreset(
      id: 'dramatic',
      name: 'Dramatik',
      matrix: _chain([ColorMatrix.contrast(1.35), ColorMatrix.saturation(0.85), ColorMatrix.offset(-8, -8, -6)]),
      vignette: -40,
    ),
    FilterPreset(
      id: 'matte',
      name: 'Mat',
      matrix: _chain([ColorMatrix.contrast(0.85), ColorMatrix.offset(22, 20, 18), ColorMatrix.saturation(0.9)]),
    ),
    FilterPreset(
      id: 'sunset',
      name: 'Gün Batımı',
      matrix: _chain([ColorMatrix.scale(1.15, 0.97, 0.82), ColorMatrix.offset(10, 0, 4), ColorMatrix.saturation(1.15)]),
      vignette: -15,
    ),
    FilterPreset(
      id: 'ocean',
      name: 'Okyanus',
      matrix: _chain([ColorMatrix.scale(0.88, 1.03, 1.15), ColorMatrix.saturation(1.1)]),
    ),
    FilterPreset(
      id: 'forest',
      name: 'Orman',
      matrix: _chain([ColorMatrix.scale(0.94, 1.08, 0.92), ColorMatrix.contrast(1.05), ColorMatrix.saturation(1.05)]),
    ),
    FilterPreset(
      id: 'lomo',
      name: 'Lomo',
      matrix: _chain([ColorMatrix.contrast(1.25), ColorMatrix.saturation(1.3)]),
      vignette: -60,
    ),
    FilterPreset(
      id: 'polaroid',
      name: 'Polaroid',
      matrix: _m(const [
        1.438, -0.062, -0.062, 0, 0, //
        -0.122, 1.378, -0.122, 0, 0, //
        -0.016, -0.016, 1.483, 0, 0, //
        0, 0, 0, 1, 0,
      ]).compose(ColorMatrix.offset(-8, -8, -8)),
    ),
    FilterPreset(
      id: 'pastel',
      name: 'Pastel',
      matrix: _chain([ColorMatrix.saturation(0.65), ColorMatrix.contrast(0.85), ColorMatrix.offset(26, 22, 30)]),
    ),
    FilterPreset(id: 'invert', name: 'Negatif', matrix: ColorMatrix.invert()),
  ];

  static FilterPreset byId(String id) {
    for (final f in all) {
      if (f.id == id) return f;
    }
    return all.first;
  }
}
