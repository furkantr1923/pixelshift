import 'dart:typed_data';

import '../image_engine/raster.dart';

/// Desteklenen AI / akıllı düzenleme görevleri.
enum AiTask {
  removeBackground('Arka plan kaldırma', 'Konuyu arka plandan ayırır, şeffaf PNG üretir.'),
  replaceBackground('Arka plan değiştirme', 'Şeffaf alanları renk, geçiş veya başka bir görselle doldurur.'),
  objectRemoval('Nesne silme', 'Fırçayla boyadığınız nesneyi kaldırıp çevresiyle doldurur.'),
  enhance('Fotoğraf iyileştirme', 'Pozlama, kontrast, renk dengesi ve netliği otomatik düzeltir.'),
  upscale('Çözünürlük yükseltme', 'Görseli 2 veya 4 kat büyütür.'),
  portrait('Portre iyileştirme', 'Ten bölgelerini yumuşatır, ışığı ve canlılığı dengeler.'),
  skinSmooth('Doğal cilt rötuşu', 'Dokuyu koruyarak cildi yumuşatır.'),
  restore('Fotoğraf restorasyonu', 'Eski fotoğraflarda toz/gürültüyü azaltır, solmuş rengi ve kontrastı geri kazandırır.'),
  style('Sanatsal stil', 'Fotoğrafı resim, karakalem veya çizgi film tarzına dönüştürür.'),
  textEdit('Metin komutuyla düzenleme', 'Yazdığınız komuta göre görseli düzenler.');

  const AiTask(this.label, this.description);
  final String label;
  final String description;

  bool get needsMask => this == AiTask.objectRemoval;
}

/// İşlem isteği. [image] katmanlar hariç, tüm ayarları uygulanmış tam
/// çözünürlüklü taban görüntüdür.
class AiRequest {
  const AiRequest({required this.task, required this.image, this.mask, this.params = const {}});

  final AiTask task;
  final Raster image;

  /// Nesne silme maskesi (0/255, görüntü boyutunda).
  final Uint8List? mask;

  /// Göreve özel parametreler: style, factor, tolerance, prompt, topColor, bottomColor...
  final Map<String, Object?> params;
}

class AiResult {
  const AiResult({required this.image, required this.providerName, this.note});
  final Raster image;
  final String providerName;
  final String? note;
}

/// Kullanıcıya gösterilen gizlilik ve maliyet bilgisi (çevrimiçi sağlayıcılar).
class ProviderPrivacy {
  const ProviderPrivacy({
    required this.host,
    required this.dataHandling,
    required this.policyUrl,
    required this.limits,
    this.license,
  });

  final String host;

  /// Verinin saklanıp saklanmadığına dair BİLİNEN bilgi; bilinmiyorsa açıkça söylenir.
  final String dataHandling;
  final String policyUrl;

  /// Ücretsiz kullanım sınırları ve ücret durumu.
  final String limits;

  /// Kullanılan modelin lisansı (biliniyorsa).
  final String? license;
}

/// İzin penceresine aktarılan bilgi.
class ConsentRequest {
  const ConsentRequest({
    required this.providerName,
    required this.task,
    required this.privacy,
    required this.uploadDescription,
    this.model,
  });

  final String providerName;
  final AiTask task;
  final ProviderPrivacy privacy;
  final String uploadDescription;
  final String? model;
}

typedef ConsentCallback = Future<bool> Function(ConsentRequest request);

/// İlerleme bildirimi: [stage] Türkçe aşama metni, [fraction] 0..1 veya belirsiz için null.
typedef ProgressCallback = void Function(String stage, double? fraction);

/// İptal belirteci.
class CancelToken {
  bool _cancelled = false;
  final List<void Function()> _listeners = [];

  bool get isCancelled => _cancelled;

  void cancel() {
    if (_cancelled) return;
    _cancelled = true;
    for (final l in List.of(_listeners)) {
      l();
    }
  }

  void onCancel(void Function() listener) {
    if (_cancelled) {
      listener();
    } else {
      _listeners.add(listener);
    }
  }
}

/// AI sağlayıcı adaptörü. Her sağlayıcı bağımsızdır; biri çalışmazsa
/// diğerleri ve uygulamanın geri kalanı etkilenmez.
abstract class AiProvider {
  String get id;
  String get name;

  /// true ise görsel internet üzerinden gönderilir ve her seferinde izin istenir.
  bool get isOnline;

  Set<AiTask> get supportedTasks;

  /// API anahtarı vb. eksikse false.
  bool get isConfigured;

  /// Yapılandırılmamışsa kullanıcıya gösterilecek açıklama.
  String get configurationHint;

  ProviderPrivacy? get privacy;

  /// Görev için kullanılacak model (çevrimiçi sağlayıcılarda).
  String? modelFor(AiTask task) => null;

  Future<AiResult> run(AiRequest request, {required ProgressCallback progress, required CancelToken cancel});
}
