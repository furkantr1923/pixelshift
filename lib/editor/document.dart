import '../filters/adjustments.dart';
import '../image_engine/geometry.dart';
import '../layers/layer.dart';

/// Bir düzenleme oturumunun tamamını tanımlayan değişmez belge.
///
/// Orijinal dosya hiçbir zaman değiştirilmez; tüm işlemler parametre olarak
/// saklanır. Geri al/yinele, belge anlık görüntülerinden oluşan bir yığındır.
/// AI ve klasik "piksel" işlemleri (arka plan kaldırma, nesne silme...) yeni
/// bir kaynak dosyası üretir ve [sourceFile] değişir; eski kaynak projede
/// tutulduğu için bu işlemler de geri alınabilir.
class EditDocument {
  const EditDocument({
    required this.sourceFile,
    required this.sourceWidth,
    required this.sourceHeight,
    this.geometry = Geometry.identity,
    this.adjustments = Adjustments.none,
    this.layers = const [],
  });

  final String sourceFile;
  final int sourceWidth;
  final int sourceHeight;
  final Geometry geometry;
  final Adjustments adjustments;
  final List<Layer> layers;

  /// Tuval (çıktı) boyutu, tam çözünürlük pikseli.
  (int, int) get canvasSize => geometry.outputSize(sourceWidth, sourceHeight);

  int get canvasWidth => canvasSize.$1;
  int get canvasHeight => canvasSize.$2;

  Layer? layerById(String? id) {
    if (id == null) return null;
    for (final l in layers) {
      if (l.id == id) return l;
    }
    return null;
  }

  EditDocument copyWith({
    String? sourceFile,
    int? sourceWidth,
    int? sourceHeight,
    Geometry? geometry,
    Adjustments? adjustments,
    List<Layer>? layers,
  }) {
    return EditDocument(
      sourceFile: sourceFile ?? this.sourceFile,
      sourceWidth: sourceWidth ?? this.sourceWidth,
      sourceHeight: sourceHeight ?? this.sourceHeight,
      geometry: geometry ?? this.geometry,
      adjustments: adjustments ?? this.adjustments,
      layers: layers ?? this.layers,
    );
  }

  EditDocument replaceLayer(Layer layer) =>
      copyWith(layers: [for (final l in layers) l.id == layer.id ? layer : l]);

  EditDocument removeLayer(String id) => copyWith(layers: [for (final l in layers) if (l.id != id) l]);

  EditDocument addLayer(Layer layer) => copyWith(layers: [...layers, layer]);

  /// Katmanı yığında [delta] kadar yukarı (+) / aşağı (-) taşır.
  EditDocument moveLayer(String id, int delta) {
    final list = [...layers];
    final i = list.indexWhere((l) => l.id == id);
    if (i < 0) return this;
    final j = (i + delta).clamp(0, list.length - 1);
    if (i == j) return this;
    final layer = list.removeAt(i);
    list.insert(j, layer);
    return copyWith(layers: list);
  }

  EditDocument reorderLayer(int oldIndex, int newIndex) {
    final list = [...layers];
    if (oldIndex < 0 || oldIndex >= list.length) return this;
    final layer = list.removeAt(oldIndex);
    list.insert(newIndex.clamp(0, list.length), layer);
    return copyWith(layers: list);
  }

  Map<String, Object?> toJson() => {
        'sourceFile': sourceFile,
        'sourceWidth': sourceWidth,
        'sourceHeight': sourceHeight,
        'geometry': geometry.toJson(),
        'adjustments': adjustments.toJson(),
        'layers': [for (final l in layers) l.toJson()],
      };

  factory EditDocument.fromJson(Map<String, Object?> j) {
    final layers = <Layer>[];
    for (final raw in (j['layers'] as List? ?? const [])) {
      try {
        layers.add(Layer.fromJson((raw as Map).cast<String, Object?>()));
      } on FormatException {
        // Bilinmeyen katman türleri (ileri sürüm) atlanır.
      }
    }
    return EditDocument(
      sourceFile: j['sourceFile'] as String? ?? 'source.png',
      sourceWidth: (j['sourceWidth'] as num?)?.toInt() ?? 1,
      sourceHeight: (j['sourceHeight'] as num?)?.toInt() ?? 1,
      geometry: Geometry.fromJson((j['geometry'] as Map?)?.cast<String, Object?>() ?? const {}),
      adjustments: Adjustments.fromJson((j['adjustments'] as Map?)?.cast<String, Object?>() ?? const {}),
      layers: layers,
    );
  }
}
