import 'dart:math' as math;

/// Katman karışım modları (Flutter `BlendMode` karşılıkları layer_painter'da).
enum LayerBlend {
  normal('Normal'),
  multiply('Çarp'),
  screen('Ekran'),
  overlay('Bindirme'),
  darken('Koyulaştır'),
  lighten('Açıklaştır'),
  colorDodge('Renk Soldurma'),
  colorBurn('Renk Yakma'),
  hardLight('Sert Işık'),
  softLight('Yumuşak Işık'),
  difference('Fark'),
  exclusion('Dışlama'),
  hue('Ton'),
  saturation('Doygunluk'),
  color('Renk'),
  luminosity('Parlaklık');

  const LayerBlend(this.label);
  final String label;

  static LayerBlend fromName(Object? name) {
    for (final b in values) {
      if (b.name == name) return b;
    }
    return normal;
  }
}

enum LayerType { text, image, shape }

/// Maske fırça darbesi (katmanın yerel koordinatlarında).
/// [hide] = true: fırça içeriği gizler; false: silgi, gizlenen alanı geri açar.
class MaskStroke {
  const MaskStroke({required this.points, required this.radius, this.feather = 0.5, this.hide = true});

  /// x0, y0, x1, y1, ... (katman merkezine göre, ölçeksiz yerel birim)
  final List<double> points;
  final double radius;
  final double feather; // 0..1 kenar yumuşatma
  final bool hide;

  MaskStroke withPoint(double x, double y) => MaskStroke(points: [...points, x, y], radius: radius, feather: feather, hide: hide);

  Map<String, Object?> toJson() => {
        'p': [for (final v in points) double.parse(v.toStringAsFixed(2))],
        'r': radius,
        'f': feather,
        'h': hide,
      };

  factory MaskStroke.fromJson(Map<String, Object?> j) => MaskStroke(
        points: [for (final v in (j['p'] as List? ?? const [])) (v as num).toDouble()],
        radius: (j['r'] as num?)?.toDouble() ?? 20,
        feather: (j['f'] as num?)?.toDouble() ?? 0.5,
        hide: j['h'] != false,
      );
}

/// Ortak katman özellikleri. Tüm konum/ölçü değerleri belge (tam çözünürlük)
/// piksel birimindedir; bu sayede önizleme ve dışa aktarma aynı sonucu verir.
abstract class Layer {
  const Layer({
    required this.id,
    required this.name,
    this.visible = true,
    this.locked = false,
    this.opacity = 1,
    this.blend = LayerBlend.normal,
    required this.cx,
    required this.cy,
    this.scale = 1,
    this.rotation = 0,
    this.mask = const [],
    this.maskEnabled = true,
  });

  final String id;
  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final LayerBlend blend;
  final double cx;
  final double cy;
  final double scale;
  final double rotation; // radyan
  final List<MaskStroke> mask;
  final bool maskEnabled;

  LayerType get type;

  /// Ölçeklenmemiş içerik boyutu. Metin katmanında yerleşimden hesaplanır
  /// ve dışarıdan verilir (bkz. LayerMetrics).
  String get typeLabel => switch (type) {
        LayerType.text => 'Metin',
        LayerType.image => 'Görsel',
        LayerType.shape => 'Şekil',
      };

  Layer copyBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    LayerBlend? blend,
    double? cx,
    double? cy,
    double? scale,
    double? rotation,
    List<MaskStroke>? mask,
    bool? maskEnabled,
  });

  Map<String, Object?> baseJson() => {
        'id': id,
        'type': type.name,
        'name': name,
        'visible': visible,
        'locked': locked,
        'opacity': opacity,
        'blend': blend.name,
        'cx': cx,
        'cy': cy,
        'scale': scale,
        'rotation': rotation,
        'mask': [for (final s in mask) s.toJson()],
        'maskEnabled': maskEnabled,
      };

  Map<String, Object?> toJson();

  static Layer fromJson(Map<String, Object?> j) {
    switch (j['type']) {
      case 'text':
        return TextLayer.fromJson(j);
      case 'image':
        return ImageLayer.fromJson(j);
      case 'shape':
        return ShapeLayer.fromJson(j);
      default:
        throw FormatException('Bilinmeyen katman türü: ${j['type']}');
    }
  }
}

class _Base {
  _Base(Map<String, Object?> j)
      : id = j['id'] as String? ?? 'katman',
        name = j['name'] as String? ?? 'Katman',
        visible = j['visible'] != false,
        locked = j['locked'] == true,
        opacity = ((j['opacity'] as num?)?.toDouble() ?? 1).clamp(0.0, 1.0).toDouble(),
        blend = LayerBlend.fromName(j['blend']),
        cx = (j['cx'] as num?)?.toDouble() ?? 0,
        cy = (j['cy'] as num?)?.toDouble() ?? 0,
        scale = (j['scale'] as num?)?.toDouble() ?? 1,
        rotation = (j['rotation'] as num?)?.toDouble() ?? 0,
        mask = [for (final s in (j['mask'] as List? ?? const [])) MaskStroke.fromJson((s as Map).cast<String, Object?>())],
        maskEnabled = j['maskEnabled'] != false;

  final String id;
  final String name;
  final bool visible;
  final bool locked;
  final double opacity;
  final LayerBlend blend;
  final double cx;
  final double cy;
  final double scale;
  final double rotation;
  final List<MaskStroke> mask;
  final bool maskEnabled;
}

int _argb(Object? v, int fallback) => v is num ? v.toInt() & 0xffffffff : fallback;

enum TextAlignOption { left, center, right }

class TextLayer extends Layer {
  const TextLayer({
    required super.id,
    required super.name,
    super.visible,
    super.locked,
    super.opacity,
    super.blend,
    required super.cx,
    required super.cy,
    super.scale,
    super.rotation,
    super.mask,
    super.maskEnabled,
    required this.text,
    this.fontFamily = 'Inter',
    this.fontSize = 72,
    this.color = 0xFFFFFFFF,
    this.align = TextAlignOption.center,
    this.bold = false,
    this.italic = false,
    this.letterSpacing = 0,
    this.lineHeight = 1.2,
    this.strokeWidth = 0,
    this.strokeColor = 0xFF000000,
    this.shadow = false,
    this.shadowColor = 0x99000000,
    this.background = 0,
    this.padding = 0,
    this.boxWidth = 0,
    this.isSticker = false,
  });

  final String text;
  final String fontFamily;
  final double fontSize;
  final int color;
  final TextAlignOption align;
  final bool bold;
  final bool italic;
  final double letterSpacing;
  final double lineHeight;
  final double strokeWidth;
  final int strokeColor;
  final bool shadow;
  final int shadowColor;
  final int background; // 0 = yok
  final double padding;
  final double boxWidth; // 0 = otomatik (satır sonu yok)
  final bool isSticker;

  @override
  LayerType get type => LayerType.text;

  @override
  String get typeLabel => isSticker ? 'Çıkartma' : 'Metin';

  TextLayer copyWith({
    String? text,
    String? fontFamily,
    double? fontSize,
    int? color,
    TextAlignOption? align,
    bool? bold,
    bool? italic,
    double? letterSpacing,
    double? lineHeight,
    double? strokeWidth,
    int? strokeColor,
    bool? shadow,
    int? shadowColor,
    int? background,
    double? padding,
    double? boxWidth,
  }) {
    return TextLayer(
      id: id,
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      blend: blend,
      cx: cx,
      cy: cy,
      scale: scale,
      rotation: rotation,
      mask: mask,
      maskEnabled: maskEnabled,
      text: text ?? this.text,
      fontFamily: fontFamily ?? this.fontFamily,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      align: align ?? this.align,
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      letterSpacing: letterSpacing ?? this.letterSpacing,
      lineHeight: lineHeight ?? this.lineHeight,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      strokeColor: strokeColor ?? this.strokeColor,
      shadow: shadow ?? this.shadow,
      shadowColor: shadowColor ?? this.shadowColor,
      background: background ?? this.background,
      padding: padding ?? this.padding,
      boxWidth: boxWidth ?? this.boxWidth,
      isSticker: isSticker,
    );
  }

  @override
  TextLayer copyBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    LayerBlend? blend,
    double? cx,
    double? cy,
    double? scale,
    double? rotation,
    List<MaskStroke>? mask,
    bool? maskEnabled,
  }) {
    return TextLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      blend: blend ?? this.blend,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      mask: mask ?? this.mask,
      maskEnabled: maskEnabled ?? this.maskEnabled,
      text: text,
      fontFamily: fontFamily,
      fontSize: fontSize,
      color: color,
      align: align,
      bold: bold,
      italic: italic,
      letterSpacing: letterSpacing,
      lineHeight: lineHeight,
      strokeWidth: strokeWidth,
      strokeColor: strokeColor,
      shadow: shadow,
      shadowColor: shadowColor,
      background: background,
      padding: padding,
      boxWidth: boxWidth,
      isSticker: isSticker,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        ...baseJson(),
        'text': text,
        'fontFamily': fontFamily,
        'fontSize': fontSize,
        'color': color,
        'align': align.name,
        'bold': bold,
        'italic': italic,
        'letterSpacing': letterSpacing,
        'lineHeight': lineHeight,
        'strokeWidth': strokeWidth,
        'strokeColor': strokeColor,
        'shadow': shadow,
        'shadowColor': shadowColor,
        'background': background,
        'padding': padding,
        'boxWidth': boxWidth,
        'isSticker': isSticker,
      };

  factory TextLayer.fromJson(Map<String, Object?> j) {
    final b = _Base(j);
    return TextLayer(
      id: b.id,
      name: b.name,
      visible: b.visible,
      locked: b.locked,
      opacity: b.opacity,
      blend: b.blend,
      cx: b.cx,
      cy: b.cy,
      scale: b.scale,
      rotation: b.rotation,
      mask: b.mask,
      maskEnabled: b.maskEnabled,
      text: j['text'] as String? ?? '',
      fontFamily: j['fontFamily'] as String? ?? 'Inter',
      fontSize: (j['fontSize'] as num?)?.toDouble() ?? 72,
      color: _argb(j['color'], 0xFFFFFFFF),
      align: TextAlignOption.values.firstWhere((a) => a.name == j['align'], orElse: () => TextAlignOption.center),
      bold: j['bold'] == true,
      italic: j['italic'] == true,
      letterSpacing: (j['letterSpacing'] as num?)?.toDouble() ?? 0,
      lineHeight: (j['lineHeight'] as num?)?.toDouble() ?? 1.2,
      strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 0,
      strokeColor: _argb(j['strokeColor'], 0xFF000000),
      shadow: j['shadow'] == true,
      shadowColor: _argb(j['shadowColor'], 0x99000000),
      background: _argb(j['background'], 0),
      padding: (j['padding'] as num?)?.toDouble() ?? 0,
      boxWidth: (j['boxWidth'] as num?)?.toDouble() ?? 0,
      isSticker: j['isSticker'] == true,
    );
  }
}

class ImageLayer extends Layer {
  const ImageLayer({
    required super.id,
    required super.name,
    super.visible,
    super.locked,
    super.opacity,
    super.blend,
    required super.cx,
    required super.cy,
    super.scale,
    super.rotation,
    super.mask,
    super.maskEnabled,
    required this.assetFile,
    required this.assetWidth,
    required this.assetHeight,
    required this.width,
    required this.height,
    this.cornerRadius = 0,
    this.borderWidth = 0,
    this.borderColor = 0xFFFFFFFF,
    this.contentScale = 1,
    this.contentOffsetX = 0,
    this.contentOffsetY = 0,
  });

  final String assetFile; // proje klasöründeki assets/ altındaki dosya adı
  final int assetWidth;
  final int assetHeight;
  final double width; // kutu (ölçeksiz)
  final double height;
  final double cornerRadius;
  final double borderWidth;
  final int borderColor;
  final double contentScale; // >= 1, kutu içinde yakınlaştırma
  final double contentOffsetX; // -1..1
  final double contentOffsetY; // -1..1

  @override
  LayerType get type => LayerType.image;

  ImageLayer copyWith({
    double? width,
    double? height,
    double? cornerRadius,
    double? borderWidth,
    int? borderColor,
    double? contentScale,
    double? contentOffsetX,
    double? contentOffsetY,
  }) {
    return ImageLayer(
      id: id,
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      blend: blend,
      cx: cx,
      cy: cy,
      scale: scale,
      rotation: rotation,
      mask: mask,
      maskEnabled: maskEnabled,
      assetFile: assetFile,
      assetWidth: assetWidth,
      assetHeight: assetHeight,
      width: width ?? this.width,
      height: height ?? this.height,
      cornerRadius: cornerRadius ?? this.cornerRadius,
      borderWidth: borderWidth ?? this.borderWidth,
      borderColor: borderColor ?? this.borderColor,
      contentScale: math.max(1.0, contentScale ?? this.contentScale),
      contentOffsetX: (contentOffsetX ?? this.contentOffsetX).clamp(-1.0, 1.0).toDouble(),
      contentOffsetY: (contentOffsetY ?? this.contentOffsetY).clamp(-1.0, 1.0).toDouble(),
    );
  }

  @override
  ImageLayer copyBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    LayerBlend? blend,
    double? cx,
    double? cy,
    double? scale,
    double? rotation,
    List<MaskStroke>? mask,
    bool? maskEnabled,
  }) {
    return ImageLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      blend: blend ?? this.blend,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      mask: mask ?? this.mask,
      maskEnabled: maskEnabled ?? this.maskEnabled,
      assetFile: assetFile,
      assetWidth: assetWidth,
      assetHeight: assetHeight,
      width: width,
      height: height,
      cornerRadius: cornerRadius,
      borderWidth: borderWidth,
      borderColor: borderColor,
      contentScale: contentScale,
      contentOffsetX: contentOffsetX,
      contentOffsetY: contentOffsetY,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        ...baseJson(),
        'assetFile': assetFile,
        'assetWidth': assetWidth,
        'assetHeight': assetHeight,
        'width': width,
        'height': height,
        'cornerRadius': cornerRadius,
        'borderWidth': borderWidth,
        'borderColor': borderColor,
        'contentScale': contentScale,
        'contentOffsetX': contentOffsetX,
        'contentOffsetY': contentOffsetY,
      };

  factory ImageLayer.fromJson(Map<String, Object?> j) {
    final b = _Base(j);
    return ImageLayer(
      id: b.id,
      name: b.name,
      visible: b.visible,
      locked: b.locked,
      opacity: b.opacity,
      blend: b.blend,
      cx: b.cx,
      cy: b.cy,
      scale: b.scale,
      rotation: b.rotation,
      mask: b.mask,
      maskEnabled: b.maskEnabled,
      assetFile: j['assetFile'] as String? ?? '',
      assetWidth: (j['assetWidth'] as num?)?.toInt() ?? 1,
      assetHeight: (j['assetHeight'] as num?)?.toInt() ?? 1,
      width: (j['width'] as num?)?.toDouble() ?? 100,
      height: (j['height'] as num?)?.toDouble() ?? 100,
      cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 0,
      borderWidth: (j['borderWidth'] as num?)?.toDouble() ?? 0,
      borderColor: _argb(j['borderColor'], 0xFFFFFFFF),
      contentScale: (j['contentScale'] as num?)?.toDouble() ?? 1,
      contentOffsetX: (j['contentOffsetX'] as num?)?.toDouble() ?? 0,
      contentOffsetY: (j['contentOffsetY'] as num?)?.toDouble() ?? 0,
    );
  }
}

enum ShapeKind {
  rect('Dikdörtgen'),
  roundRect('Yuvarlak köşe'),
  ellipse('Elips'),
  triangle('Üçgen'),
  star('Yıldız'),
  heart('Kalp'),
  line('Çizgi'),
  arrow('Ok'),
  bubble('Konuşma balonu'),
  badge('Rozet');

  const ShapeKind(this.label);
  final String label;
}

class ShapeLayer extends Layer {
  const ShapeLayer({
    required super.id,
    required super.name,
    super.visible,
    super.locked,
    super.opacity,
    super.blend,
    required super.cx,
    required super.cy,
    super.scale,
    super.rotation,
    super.mask,
    super.maskEnabled,
    required this.shape,
    required this.width,
    required this.height,
    this.fill = 0xFF7C5CFF,
    this.stroke = 0x00000000,
    this.strokeWidth = 0,
    this.cornerRadius = 24,
    this.fillEnd = 0,
  });

  final ShapeKind shape;
  final double width;
  final double height;
  final int fill;
  final int fillEnd; // 0 = düz renk, aksi halde dikey geçiş bitiş rengi
  final int stroke;
  final double strokeWidth;
  final double cornerRadius;

  @override
  LayerType get type => LayerType.shape;

  ShapeLayer copyWith({
    ShapeKind? shape,
    double? width,
    double? height,
    int? fill,
    int? fillEnd,
    int? stroke,
    double? strokeWidth,
    double? cornerRadius,
  }) {
    return ShapeLayer(
      id: id,
      name: name,
      visible: visible,
      locked: locked,
      opacity: opacity,
      blend: blend,
      cx: cx,
      cy: cy,
      scale: scale,
      rotation: rotation,
      mask: mask,
      maskEnabled: maskEnabled,
      shape: shape ?? this.shape,
      width: width ?? this.width,
      height: height ?? this.height,
      fill: fill ?? this.fill,
      fillEnd: fillEnd ?? this.fillEnd,
      stroke: stroke ?? this.stroke,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      cornerRadius: cornerRadius ?? this.cornerRadius,
    );
  }

  @override
  ShapeLayer copyBase({
    String? name,
    bool? visible,
    bool? locked,
    double? opacity,
    LayerBlend? blend,
    double? cx,
    double? cy,
    double? scale,
    double? rotation,
    List<MaskStroke>? mask,
    bool? maskEnabled,
  }) {
    return ShapeLayer(
      id: id,
      name: name ?? this.name,
      visible: visible ?? this.visible,
      locked: locked ?? this.locked,
      opacity: opacity ?? this.opacity,
      blend: blend ?? this.blend,
      cx: cx ?? this.cx,
      cy: cy ?? this.cy,
      scale: scale ?? this.scale,
      rotation: rotation ?? this.rotation,
      mask: mask ?? this.mask,
      maskEnabled: maskEnabled ?? this.maskEnabled,
      shape: shape,
      width: width,
      height: height,
      fill: fill,
      fillEnd: fillEnd,
      stroke: stroke,
      strokeWidth: strokeWidth,
      cornerRadius: cornerRadius,
    );
  }

  @override
  Map<String, Object?> toJson() => {
        ...baseJson(),
        'shape': shape.name,
        'width': width,
        'height': height,
        'fill': fill,
        'fillEnd': fillEnd,
        'stroke': stroke,
        'strokeWidth': strokeWidth,
        'cornerRadius': cornerRadius,
      };

  factory ShapeLayer.fromJson(Map<String, Object?> j) {
    final b = _Base(j);
    return ShapeLayer(
      id: b.id,
      name: b.name,
      visible: b.visible,
      locked: b.locked,
      opacity: b.opacity,
      blend: b.blend,
      cx: b.cx,
      cy: b.cy,
      scale: b.scale,
      rotation: b.rotation,
      mask: b.mask,
      maskEnabled: b.maskEnabled,
      shape: ShapeKind.values.firstWhere((s) => s.name == j['shape'], orElse: () => ShapeKind.rect),
      width: (j['width'] as num?)?.toDouble() ?? 200,
      height: (j['height'] as num?)?.toDouble() ?? 200,
      fill: _argb(j['fill'], 0xFF7C5CFF),
      fillEnd: _argb(j['fillEnd'], 0),
      stroke: _argb(j['stroke'], 0),
      strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 0,
      cornerRadius: (j['cornerRadius'] as num?)?.toDouble() ?? 24,
    );
  }
}
