import '../core/ids.dart';
import '../layers/layer.dart';

/// Tuval boyutu ön ayarı.
class CanvasPreset {
  const CanvasPreset(this.name, this.width, this.height);
  final String name;
  final int width;
  final int height;

  static const List<CanvasPreset> all = [
    CanvasPreset('Instagram gönderi (kare)', 1080, 1080),
    CanvasPreset('Instagram dikey', 1080, 1350),
    CanvasPreset('Hikâye / Reels', 1080, 1920),
    CanvasPreset('YouTube kapak', 1280, 720),
    CanvasPreset('Facebook kapak', 1640, 624),
    CanvasPreset('X (Twitter) başlık', 1500, 500),
    CanvasPreset('Full HD', 1920, 1080),
    CanvasPreset('A4 poster (300 dpi)', 2480, 3508),
    CanvasPreset('A5 broşür (300 dpi)', 1748, 2480),
  ];
}

/// Hazır tasarım şablonu: arka plan + düzenlenebilir katmanlar.
class DesignTemplate {
  const DesignTemplate({
    required this.id,
    required this.name,
    required this.category,
    required this.width,
    required this.height,
    required this.top,
    required this.bottom,
    required this.build,
  });

  final String id;
  final String name;
  final String category;
  final int width;
  final int height;
  final int top;
  final int bottom;
  final List<Layer> Function(double w, double h) build;

  static TextLayer _t(String text, double x, double y, double size,
      {String font = 'Inter',
      int color = 0xFFFFFFFF,
      bool bold = true,
      double boxWidth = 0,
      int background = 0,
      double padding = 0,
      double letterSpacing = 0,
      bool shadow = false,
      TextAlignOption align = TextAlignOption.center}) {
    return TextLayer(
      id: newId('l'),
      name: text.length > 18 ? '${text.substring(0, 16)}…' : text,
      cx: x,
      cy: y,
      text: text,
      fontFamily: font,
      fontSize: size,
      color: color,
      bold: bold,
      boxWidth: boxWidth,
      background: background,
      padding: padding,
      letterSpacing: letterSpacing,
      shadow: shadow,
      align: align,
    );
  }

  static ShapeLayer _s(ShapeKind kind, double x, double y, double w, double h,
      {int fill = 0xFF7C5CFF, int fillEnd = 0, double radius = 24, double opacity = 1, double rotation = 0}) {
    return ShapeLayer(
      id: newId('l'),
      name: kind.label,
      cx: x,
      cy: y,
      shape: kind,
      width: w,
      height: h,
      fill: fill,
      fillEnd: fillEnd,
      cornerRadius: radius,
      opacity: opacity,
      rotation: rotation,
    );
  }

  static final List<DesignTemplate> all = [
    DesignTemplate(
      id: 'event-poster',
      name: 'Etkinlik afişi',
      category: 'Poster',
      width: 2480,
      height: 3508,
      top: 0xFF1B1036,
      bottom: 0xFF0B0E16,
      build: (w, h) => [
        _s(ShapeKind.ellipse, w * 0.78, h * 0.18, w * 0.9, w * 0.9, fill: 0xFF7C5CFF, fillEnd: 0xFF22D3EE, opacity: 0.55),
        _s(ShapeKind.ellipse, w * 0.12, h * 0.62, w * 0.5, w * 0.5, fill: 0xFFFF5CD6, opacity: 0.35),
        _t('YAZ FESTİVALİ', w / 2, h * 0.42, w * 0.11, font: 'Anton', letterSpacing: 6),
        _t('Müzik • Sanat • Lezzet', w / 2, h * 0.5, w * 0.045, font: 'Poppins', bold: false, color: 0xFFCFD3E6),
        _t('15 TEMMUZ 2026', w / 2, h * 0.62, w * 0.06, font: 'Poppins', background: 0xFF22D3EE, color: 0xFF0B0E16, padding: w * 0.025),
        _t('Kordon Açık Hava Sahnesi', w / 2, h * 0.88, w * 0.04, font: 'Inter', bold: false, color: 0xFFA0A6B8),
      ],
    ),
    DesignTemplate(
      id: 'minimal-quote',
      name: 'Minimal alıntı',
      category: 'Sosyal medya',
      width: 1080,
      height: 1080,
      top: 0xFFF5E6CC,
      bottom: 0xFFEAD7B7,
      build: (w, h) => [
        _t('“', w / 2, h * 0.26, w * 0.3, font: 'Crimson Text', color: 0xFF8B5A2B),
        _t('Küçük adımlar büyük yolculukların başlangıcıdır.', w / 2, h * 0.5, w * 0.07,
            font: 'Crimson Text', color: 0xFF2A2F3D, boxWidth: w * 0.78),
        _s(ShapeKind.rect, w / 2, h * 0.7, w * 0.12, 6, fill: 0xFF8B5A2B, radius: 0),
        _t('— PIXELSHIFT', w / 2, h * 0.77, w * 0.035, font: 'Inter', color: 0xFF5B6275, bold: false, letterSpacing: 3),
      ],
    ),
    DesignTemplate(
      id: 'sale-story',
      name: 'İndirim hikâyesi',
      category: 'Sosyal medya',
      width: 1080,
      height: 1920,
      top: 0xFFFF5C7A,
      bottom: 0xFFFF8A3D,
      build: (w, h) => [
        _s(ShapeKind.badge, w / 2, h * 0.36, w * 0.72, w * 0.72, fill: 0xFFFFFFFF),
        _t('%50', w / 2, h * 0.33, w * 0.24, font: 'Anton', color: 0xFFFF5C7A),
        _t('İNDİRİM', w / 2, h * 0.43, w * 0.08, font: 'Archivo Black', color: 0xFF111827),
        _t('Sadece bu hafta sonu', w / 2, h * 0.62, w * 0.06, font: 'Poppins', bold: false),
        _t('ŞİMDİ KEŞFET', w / 2, h * 0.8, w * 0.055, font: 'Poppins', background: 0xFF111827, padding: w * 0.04, letterSpacing: 2),
      ],
    ),
    DesignTemplate(
      id: 'youtube-thumb',
      name: 'YouTube kapak',
      category: 'Kapak',
      width: 1280,
      height: 720,
      top: 0xFF0F172A,
      bottom: 0xFF1E3A5F,
      build: (w, h) => [
        _s(ShapeKind.rect, w * 0.78, h / 2, w * 0.5, h * 1.4, fill: 0xFFFFC53D, rotation: 0.22, radius: 0),
        _t('10 İPUCU', w * 0.32, h * 0.38, w * 0.11, font: 'Anton', shadow: true),
        _t('Daha iyi fotoğraflar için', w * 0.32, h * 0.58, w * 0.04, font: 'Poppins', bold: false, color: 0xFFE7E9F1),
        _s(ShapeKind.arrow, w * 0.32, h * 0.78, w * 0.2, h * 0.12, fill: 0xFFFF5C7A, radius: 0),
      ],
    ),
    DesignTemplate(
      id: 'podcast-cover',
      name: 'Podcast kapağı',
      category: 'Kapak',
      width: 3000,
      height: 3000,
      top: 0xFF111827,
      bottom: 0xFF4C1D95,
      build: (w, h) => [
        _s(ShapeKind.ellipse, w / 2, h * 0.38, w * 0.5, w * 0.5, fill: 0xFF22D3EE, fillEnd: 0xFF7C5CFF),
        _t('🎙️', w / 2, h * 0.38, w * 0.2, bold: false),
        _t('GÜNDEM SOHBETLERİ', w / 2, h * 0.72, w * 0.075, font: 'Archivo Black', letterSpacing: 4),
        _t('Her pazartesi yeni bölüm', w / 2, h * 0.8, w * 0.035, font: 'Inter', bold: false, color: 0xFFC4B5FD),
      ],
    ),
    DesignTemplate(
      id: 'birthday',
      name: 'Doğum günü kartı',
      category: 'Kart',
      width: 1500,
      height: 2100,
      top: 0xFFFFE680,
      bottom: 0xFFFFC53D,
      build: (w, h) => [
        _t('🎉', w * 0.2, h * 0.14, w * 0.14, bold: false),
        _t('🎈', w * 0.82, h * 0.2, w * 0.16, bold: false),
        _t('İyi ki', w / 2, h * 0.4, w * 0.1, font: 'Comic Relief', color: 0xFF7F1D1D),
        _t('DOĞDUN!', w / 2, h * 0.5, w * 0.15, font: 'Anton', color: 0xFFFF5C7A),
        _s(ShapeKind.heart, w / 2, h * 0.7, w * 0.22, w * 0.2, fill: 0xFFFF5C7A),
        _t('Nice mutlu yıllara', w / 2, h * 0.86, w * 0.05, font: 'Poppins', bold: false, color: 0xFF7F1D1D),
      ],
    ),
  ];
}
