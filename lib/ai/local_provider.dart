import 'dart:isolate';
import 'dart:typed_data';

import '../core/errors.dart';
import '../image_engine/classic.dart';
import '../image_engine/raster.dart';
import 'ai_models.dart';

/// Çevrimdışı "klasik algoritma" sağlayıcısı.
///
/// Yapay zekâ modeli kullanmaz; görüntü işleme algoritmalarıyla çalışır ve
/// fotoğraf cihazdan çıkmaz. Arayüzde "Yerel (AI değil)" olarak etiketlenir.
class LocalClassicProvider extends AiProvider {
  @override
  String get id => 'local';

  @override
  String get name => 'Yerel — klasik algoritma (AI değil, çevrimdışı)';

  @override
  bool get isOnline => false;

  @override
  bool get isConfigured => true;

  @override
  String get configurationHint => '';

  @override
  ProviderPrivacy? get privacy => null;

  @override
  Set<AiTask> get supportedTasks => const {
        AiTask.removeBackground,
        AiTask.replaceBackground,
        AiTask.objectRemoval,
        AiTask.enhance,
        AiTask.upscale,
        AiTask.portrait,
        AiTask.skinSmooth,
        AiTask.restore,
        AiTask.style,
      };

  @override
  Future<AiResult> run(AiRequest request, {required ProgressCallback progress, required CancelToken cancel}) async {
    if (!supportedTasks.contains(request.task)) {
      throw UserFacingException('${request.task.label} yerel olarak yapılamıyor; çevrimiçi bir sağlayıcı gerekir.');
    }
    progress('Cihazda işleniyor…', null);
    final task = request.task;
    final image = request.image;
    final mask = request.mask;
    final params = Map<String, Object?>.from(request.params);
    Raster? bgImage;
    final bgRaw = params.remove('backgroundImage');
    if (bgRaw is Raster) bgImage = bgRaw;
    final result = await _inIsolate(task, image, mask, params, bgImage);
    if (cancel.isCancelled) throw const OperationCancelled();
    return AiResult(image: result, providerName: name, note: _note(task));
  }

  static String? _note(AiTask t) => switch (t) {
        AiTask.removeBackground => 'Yerel yöntem düz/tek renkli arka planlarda en iyi sonucu verir.',
        AiTask.upscale => 'Yerel büyütme yeni ayrıntı üretmez; pürüzsüz büyütür ve keskinleştirir.',
        AiTask.portrait || AiTask.skinSmooth => 'Yüz algılama yoktur; ten rengi bölgeler yumuşatılır.',
        _ => null,
      };

  // Statik: kapanış (closure) yalnızca parametreleri yakalar, `this`'i değil.
  static Future<Raster> _inIsolate(
      AiTask task, Raster image, Uint8List? mask, Map<String, Object?> params, Raster? bgImage) {
    return Isolate.run(() => runSync(task, image, mask, params, bgImage));
  }

  /// Isolate içinde çalışan eşzamanlı uygulama (testlerde doğrudan çağrılır).
  static Raster runSync(AiTask task, Raster image, Uint8List? mask, Map<String, Object?> params, Raster? bgImage) {
    switch (task) {
      case AiTask.removeBackground:
        return Classic.removeUniformBackground(image, tolerance: (params['tolerance'] as num?)?.toDouble() ?? 32);
      case AiTask.replaceBackground:
        return Classic.replaceBackground(
          image,
          topArgb: (params['topColor'] as num?)?.toInt(),
          bottomArgb: (params['bottomColor'] as num?)?.toInt(),
          image: bgImage,
        );
      case AiTask.objectRemoval:
        if (mask == null) throw const UserFacingException('Silinecek alanı fırçayla boyayın.');
        return Classic.inpaint(image, mask);
      case AiTask.enhance:
        return Classic.enhance(image);
      case AiTask.upscale:
        return Classic.upscale(image, (params['factor'] as num?)?.toInt() ?? 2);
      case AiTask.portrait:
        return Classic.portrait(image);
      case AiTask.skinSmooth:
        return Classic.skinSmooth(image, ((params['amount'] as num?)?.toDouble() ?? 60) / 100);
      case AiTask.restore:
        return Classic.restore(image);
      case AiTask.style:
        return Classic.style(image, params['style'] as String? ?? 'oil');
      case AiTask.textEdit:
        throw const UserFacingException('Metin komutları yerelde ayar olarak uygulanır.');
    }
  }
}
