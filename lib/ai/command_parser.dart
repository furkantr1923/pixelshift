import '../core/format.dart';
import '../filters/adjustments.dart';
import '../image_engine/geometry.dart';

/// Yerel Türkçe komut yorumlayıcısının sonucu.
class CommandResult {
  const CommandResult({required this.adjustments, required this.geometry, required this.applied});

  final Adjustments adjustments;
  final Geometry geometry;

  /// Uygulanan işlemlerin Türkçe açıklamaları.
  final List<String> applied;

  bool get isEmpty => applied.isEmpty;
}

/// "daha parlak ve biraz sıcak yap", "siyah beyaz", "kontrastı çok artır",
/// "90 derece döndür" gibi komutları tahribatsız ayarlara çevirir.
///
/// Bu bir yapay zekâ modeli DEĞİLDİR: kural tabanlı, çevrimdışı çalışan bir
/// yorumlayıcıdır. Serbest biçimli düzenleme (ör. "gökyüzüne bulut ekle")
/// için çevrimiçi sağlayıcı gerekir.
class CommandParser {
  CommandParser._();

  static const List<String> examples = [
    'daha parlak yap',
    'kontrastı biraz artır',
    'siyah beyaz yap',
    'sıcak tonlar ve canlı renkler',
    'çok keskinleştir',
    'vintage filtre uygula',
    'sağa döndür',
    'gölgeleri aç',
  ];

  static CommandResult parse(String input, Adjustments current, Geometry geometry) {
    final text = trLower(input).replaceAll(RegExp(r'[.,;!?]'), ' ');
    var a = current;
    var g = geometry;
    final applied = <String>[];

    // Komutu "ve", "ile" bağlaçlarından cümleciklere ayır.
    final clauses = text.split(RegExp(r'\s+(ve|ile|ayrıca|sonra|,)\s+'));
    for (final clause in clauses) {
      final c = ' ${clause.trim()} ';
      if (c.trim().isEmpty) continue;
      final strength = _strength(c);
      final down = _has(c, ['azalt', 'düşür', 'daha az', 'kıs', 'eksilt']);
      double step(double base) => base * strength * (down ? -1 : 1);

      if (_has(c, ['sıfırla', 'orijinal', 'geri al tüm', 'temizle'])) {
        a = Adjustments.none;
        applied.add('Tüm ayarlar sıfırlandı');
        continue;
      }
      if (_has(c, ['siyah beyaz', 'siyah-beyaz', 'gri ton', 'renksiz yap', 'tek renk'])) {
        a = a.copyWith(grayscale: true);
        applied.add('Gri tonlama açıldı');
        continue;
      }
      if (_has(c, ['renkli yap', 'rengi geri'])) {
        a = a.copyWith(grayscale: false);
        applied.add('Gri tonlama kapatıldı');
      }
      final filter = _filterFor(c);
      if (filter != null) {
        a = a.copyWith(filterId: filter.$1, filterIntensity: 100);
        applied.add('${filter.$2} filtresi uygulandı');
        continue;
      }
      if (_has(c, ['sola döndür', 'saat yönünün tersine'])) {
        g = g.copyWith(quarterTurns: (g.quarterTurns + 3) % 4);
        applied.add('Sola 90° döndürüldü');
        continue;
      }
      if (_has(c, ['döndür', 'çevir 90', 'sağa döndür'])) {
        final turns = c.contains('180') ? 2 : 1;
        g = g.copyWith(quarterTurns: (g.quarterTurns + turns) % 4);
        applied.add('${turns * 90}° döndürüldü');
        continue;
      }
      if (_has(c, ['ayna', 'yatay çevir'])) {
        g = g.copyWith(flipH: !g.flipH);
        applied.add('Yatay çevrildi');
        continue;
      }
      if (_has(c, ['dikey çevir', 'baş aşağı', 'ters çevir'])) {
        g = g.copyWith(flipV: !g.flipV);
        applied.add('Dikey çevrildi');
        continue;
      }
      if (_has(c, ['kontrast'])) {
        a = a.copyWith(contrast: _clamp(a.contrast + step(20)));
        applied.add('Kontrast ${down ? 'azaltıldı' : 'artırıldı'}');
      } else if (_has(c, ['karart', 'koyu', 'karanlık'])) {
        a = a.copyWith(exposure: _clamp(a.exposure - 18 * strength));
        applied.add('Koyulaştırıldı');
      } else if (_has(c, ['parlak', 'aydınlat', 'aydınlık', 'açık yap', 'ışık'])) {
        a = a.copyWith(exposure: _clamp(a.exposure + step(18)));
        applied.add(down ? 'Parlaklık azaltıldı' : 'Aydınlatıldı');
      }
      if (_has(c, ['gölge'])) {
        final open = _has(c, ['aç', 'kaldır', 'aydınlat', 'artır']);
        a = a.copyWith(shadows: _clamp(a.shadows + (open ? 25 : -25) * strength));
        applied.add(open ? 'Gölgeler açıldı' : 'Gölgeler koyulaştırıldı');
      }
      if (_has(c, ['açık ton', 'parlama', 'patlamış', 'yanık'])) {
        a = a.copyWith(highlights: _clamp(a.highlights - 25 * strength));
        applied.add('Açık tonlar kurtarıldı');
      }
      if (_has(c, ['canlı', 'doygun', 'renkleri artır', 'renkli'])) {
        a = a.copyWith(saturation: _clamp(a.saturation + step(22)));
        applied.add('Renkler ${down ? 'azaltıldı' : 'canlandırıldı'}');
      } else if (_has(c, ['soluk', 'doygunluğu azalt', 'renkleri azalt'])) {
        a = a.copyWith(saturation: _clamp(a.saturation - 22 * strength));
        applied.add('Renkler solduruldu');
      }
      if (_has(c, ['sıcak', 'sarı ton', 'turuncu'])) {
        a = a.copyWith(temperature: _clamp(a.temperature + 22 * strength));
        applied.add('Sıcak ton verildi');
      } else if (_has(c, ['soğuk', 'mavi ton', 'mavimsi'])) {
        a = a.copyWith(temperature: _clamp(a.temperature - 22 * strength));
        applied.add('Soğuk ton verildi');
      }
      if (_has(c, ['keskin', 'net yap', 'netleştir', 'netlik'])) {
        a = a.copyWith(sharpness: (a.sharpness + 25 * strength).clamp(0, 100).toDouble());
        applied.add('Keskinleştirildi');
      }
      if (_has(c, ['bulanık', 'yumuşat', 'blur'])) {
        a = a.copyWith(blur: (a.blur + 15 * strength).clamp(0, 100).toDouble());
        applied.add('Bulanıklaştırıldı');
      }
      if (_has(c, ['vinyet', 'kenarları karart'])) {
        a = a.copyWith(vignette: _clamp(a.vignette - 35 * strength));
        applied.add('Vinyet eklendi');
      }
      if (_has(c, ['gren', 'film dokusu', 'kumlu'])) {
        a = a.copyWith(grain: (a.grain + 25 * strength).clamp(0, 100).toDouble());
        applied.add('Gren eklendi');
      }
    }
    return CommandResult(adjustments: a, geometry: g, applied: applied);
  }

  static bool _has(String c, List<String> words) => words.any(c.contains);

  static double _strength(String c) {
    if (_has(c, [' çok ', ' epey ', ' iyice ', ' fazla ', 'oldukça', 'bayağı'])) return 2;
    if (_has(c, [' biraz ', ' hafif', ' azıcık', ' az '])) return 0.5;
    return 1;
  }

  static double _clamp(double v) => v.clamp(-100, 100).toDouble();

  static (String, String)? _filterFor(String c) {
    const map = {
      'sepya': ('sepia', 'Sepya'),
      'vintage': ('vintage', 'Vintage'),
      'retro': ('vintage', 'Vintage'),
      'nostaljik': ('vintage', 'Vintage'),
      'noir': ('noir', 'Noir'),
      'dramatik': ('dramatic', 'Dramatik'),
      'film filtre': ('film', 'Film'),
      'film efekt': ('film', 'Film'),
      'analog': ('film', 'Film'),
      'lomo': ('lomo', 'Lomo'),
      'polaroid': ('polaroid', 'Polaroid'),
      'pastel': ('pastel', 'Pastel'),
      'gün batımı': ('sunset', 'Gün Batımı'),
      'okyanus': ('ocean', 'Okyanus'),
      'orman': ('forest', 'Orman'),
      'mat ': ('matte', 'Mat'),
      'negatif': ('invert', 'Negatif'),
    };
    for (final e in map.entries) {
      if (c.contains(e.key)) return e.value;
    }
    return null;
  }
}
