import '../core/errors.dart';
import 'ai_models.dart';

/// AI görevlerini yürüten hizmet. Gizlilik kuralını merkezi olarak uygular:
/// çevrimiçi sağlayıcıya görsel GÖNDERİLMEDEN önce kullanıcıdan açık izin alınır;
/// izin verilmezse sağlayıcı hiç çağrılmaz.
class AiService {
  AiService({required this.consent});

  final ConsentCallback consent;

  Future<AiResult> run(
    AiProvider provider,
    AiRequest request, {
    required ProgressCallback progress,
    required CancelToken cancel,
  }) async {
    if (!provider.supportedTasks.contains(request.task)) {
      throw UserFacingException('${provider.name} "${request.task.label}" görevini desteklemiyor.');
    }
    if (!provider.isConfigured) throw UserFacingException(provider.configurationHint);
    if (provider.isOnline) {
      final privacy = provider.privacy;
      if (privacy == null) {
        throw const UserFacingException('Sağlayıcının gizlilik bilgisi eksik; güvenlik nedeniyle gönderim yapılmadı.');
      }
      final model = provider.modelFor(request.task);
      final granted = await consent(ConsentRequest(
        providerName: provider.name,
        task: request.task,
        privacy: privacy,
        model: model,
        uploadDescription: 'Fotoğrafınızın düzenlenmiş hâli (katmanlar hariç, ${request.image.width}x${request.image.height} '
            'piksel; gönderimden önce küçültülür) ${privacy.host} adresine HTTPS ile gönderilecek. '
            'Proje dosyalarınız, diğer fotoğraflarınız ve konum/EXIF bilgileri gönderilmez.',
      ));
      if (!granted) throw const OperationCancelled();
    }
    if (cancel.isCancelled) throw const OperationCancelled();
    return provider.run(request, progress: progress, cancel: cancel);
  }
}
