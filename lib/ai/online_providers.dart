import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../core/errors.dart';
import '../image_engine/classic.dart';
import '../image_engine/codec.dart';
import '../image_engine/ops.dart';
import '../image_engine/raster.dart';
import 'ai_models.dart';

typedef HttpClientFactory = http.Client Function();

/// Görseli yükleme için hazırlar: uzun kenar [maxSide] ile sınırlanır,
/// şeffaflık varsa PNG, yoksa JPEG (%92) olarak kodlanır.
class UploadImage {
  const UploadImage(this.bytes, this.mimeType, this.width, this.height);
  final Uint8List bytes;
  final String mimeType;
  final int width;
  final int height;

  static Future<UploadImage> prepare(Raster r, int maxSide) => Isolate.run(() {
        final small = Ops.fitWithin(r, maxSide);
        final png = small.hasTransparency;
        final bytes = ImageCodec.encode(small, png ? ExportFormat.png : ExportFormat.jpg, quality: 92);
        return UploadImage(bytes, png ? 'image/png' : 'image/jpeg', small.width, small.height);
      });
}

/// Sonuç maskesini/kesimini tam çözünürlüklü görüntünün alfasına uygular.
Future<Raster> applyAlphaInIsolate(Raster full, Raster maskOrCutout) =>
    Isolate.run(() => Classic.applyAlphaMask(full, maskOrCutout));

Future<Raster> _decodeResult(Uint8List bytes) =>
    Isolate.run(() => ImageCodec.decode(bytes, 'sonuc.${_sniffExt(bytes)}'));

String _sniffExt(Uint8List b) {
  if (b.length > 3 && b[0] == 0x89 && b[1] == 0x50) return 'png';
  if (b.length > 3 && b[0] == 0xff && b[1] == 0xd8) return 'jpg';
  if (b.length > 12 && b[8] == 0x57 && b[9] == 0x45) return 'webp';
  return 'png';
}

/// Ortak HTTP yardımcıları: iptal, zaman aşımı ve Türkçe hata eşleme.
mixin _HttpSupport {
  HttpClientFactory get clientFactory;

  Future<http.Response> send(http.BaseRequest request, CancelToken cancel, {Duration timeout = const Duration(seconds: 120)}) async {
    final client = clientFactory();
    cancel.onCancel(client.close);
    try {
      final streamed = await client.send(request).timeout(timeout);
      final response = await http.Response.fromStream(streamed).timeout(timeout);
      if (cancel.isCancelled) throw const OperationCancelled();
      return response;
    } on OperationCancelled {
      rethrow;
    } on http.ClientException catch (e) {
      if (cancel.isCancelled) throw const OperationCancelled();
      throw UserFacingException('Sunucuya bağlanılamadı. İnternet bağlantınızı kontrol edin.', details: '$e');
    } on SocketException {
      if (cancel.isCancelled) throw const OperationCancelled();
      throw const UserFacingException('İnternet bağlantısı yok veya sunucuya ulaşılamıyor.');
    } on TimeoutException {
      throw const UserFacingException('Sağlayıcı zamanında yanıt vermedi (zaman aşımı). Daha sonra tekrar deneyin.');
    } finally {
      client.close();
    }
  }

  String? errorBody(http.Response r) {
    try {
      final j = jsonDecode(utf8.decode(r.bodyBytes));
      if (j is Map) {
        final e = j['error'] ?? j['errors'] ?? j['message'];
        if (e is String) return e;
        if (e is List && e.isNotEmpty) {
          final first = e.first;
          if (first is Map) return '${first['title'] ?? first['detail'] ?? first}';
          return '$first';
        }
        if (e != null) return '$e';
      }
    } catch (_) {}
    return null;
  }
}

/// Hugging Face Inference Providers (hf-inference) adaptörü.
///
/// Kullanıcının kendi ücretsiz erişim anahtarı (token) ile çalışır.
/// Anahtar kaynak koda gömülmez; Ayarlar ekranından girilir.
class HuggingFaceProvider extends AiProvider with _HttpSupport {
  HuggingFaceProvider({
    required this.token,
    Map<AiTask, String>? models,
    HttpClientFactory? clientFactory,
    this.baseUrl = 'https://router.huggingface.co/hf-inference/models',
  })  : models = {...defaultModels, ...?models},
        clientFactory = clientFactory ?? http.Client.new;

  final String? token;
  final Map<AiTask, String> models;
  final String baseUrl;

  @override
  final HttpClientFactory clientFactory;

  /// Varsayılan modeller ve lisansları. Kullanıcı Ayarlar'dan değiştirebilir.
  static const Map<AiTask, String> defaultModels = {
    AiTask.removeBackground: 'briaai/RMBG-1.4',
    AiTask.upscale: 'caidas/swin2SR-classical-sr-x2-64',
    AiTask.style: 'timbrooks/instruct-pix2pix',
    AiTask.textEdit: 'timbrooks/instruct-pix2pix',
  };

  static const Map<String, String> knownLicenses = {
    'briaai/RMBG-1.4': 'bria-rmbg-1.4 (yalnızca ticari olmayan kullanım)',
    'ZhengPeng7/BiRefNet': 'MIT',
    'caidas/swin2SR-classical-sr-x2-64': 'Apache-2.0',
    'timbrooks/instruct-pix2pix': 'MIT',
  };

  static const Map<String, String> stylePrompts = {
    'oil': 'turn it into an oil painting',
    'watercolor': 'make it a watercolor painting',
    'sketch': 'make it a pencil sketch',
    'cartoon': 'make it look like a cartoon',
    'anime': 'make it look like an anime illustration',
    'vangogh': 'make it look like a Van Gogh painting',
  };

  @override
  String get id => 'huggingface';

  @override
  String get name => 'Hugging Face (çevrimiçi)';

  @override
  bool get isOnline => true;

  @override
  bool get isConfigured => (token ?? '').trim().isNotEmpty;

  @override
  String get configurationHint =>
      'Ayarlar › AI sağlayıcıları bölümüne ücretsiz Hugging Face erişim anahtarınızı (hf_...) girin. '
      'Anahtar: huggingface.co › Settings › Access Tokens (Read yetkisi yeterli).';

  @override
  Set<AiTask> get supportedTasks => const {AiTask.removeBackground, AiTask.upscale, AiTask.style, AiTask.textEdit};

  @override
  String? modelFor(AiTask task) => models[task];

  @override
  ProviderPrivacy get privacy => const ProviderPrivacy(
        host: 'router.huggingface.co',
        dataHandling:
            'Görsel, seçilen modeli çalıştırmak için Hugging Face sunucularına gönderilir. Hugging Face\'in '
            'Inference Providers belgelerine göre istek içerikleri model iyileştirme için kullanılmaz; ancak '
            'saklama süresi ve kayıt politikası PIXELSHIFT tarafından doğrulanamaz. Ayrıntı için politikayı okuyun.',
        policyUrl: 'https://huggingface.co/privacy',
        limits:
            'Ücretsiz hesaplara aylık sınırlı çıkarım kredisi tanınır (miktar Hugging Face tarafından belirlenir ve '
            'değişebilir). Kredi bittiğinde istek reddedilir; PIXELSHIFT ücretli kullanım başlatmaz. '
            'Ücretsiz hesaplarda kredi aşımı faturalandırılmaz.',
      );

  @override
  Future<AiResult> run(AiRequest request, {required ProgressCallback progress, required CancelToken cancel}) async {
    if (!isConfigured) throw UserFacingException(configurationHint);
    final model = models[request.task];
    if (model == null || !supportedTasks.contains(request.task)) {
      throw UserFacingException('${request.task.label} bu sağlayıcıda desteklenmiyor.');
    }
    progress('Görsel hazırlanıyor…', null);
    final upload = await UploadImage.prepare(request.image, request.task == AiTask.upscale ? 1024 : 1536);
    if (cancel.isCancelled) throw const OperationCancelled();

    final uri = Uri.parse('$baseUrl/$model');
    http.Response? response;
    for (var attempt = 0; attempt < 3; attempt++) {
      final http.Request req = http.Request('POST', uri);
      req.headers['Authorization'] = 'Bearer ${token!.trim()}';
      req.headers['Accept'] = 'image/png, image/jpeg, application/json';
      if (request.task == AiTask.style || request.task == AiTask.textEdit) {
        final prompt = request.task == AiTask.style
            ? (stylePrompts[request.params['style']] ?? stylePrompts['oil']!)
            : (request.params['prompt'] as String? ?? '').trim();
        if (prompt.isEmpty) throw const UserFacingException('Bir komut yazın.');
        req.headers['Content-Type'] = 'application/json';
        req.body = jsonEncode({
          'inputs': base64Encode(upload.bytes),
          'parameters': {'prompt': prompt},
        });
      } else {
        req.headers['Content-Type'] = upload.mimeType;
        req.bodyBytes = upload.bytes;
      }
      progress(attempt == 0 ? 'Yükleniyor ve işleniyor ($model)…' : 'Yeniden deneniyor…', null);
      response = await send(req, cancel);
      if (response.statusCode == 503) {
        // Model soğuk başlıyor: tahmini süre kadar bekle.
        double wait = 10;
        try {
          final j = jsonDecode(response.body);
          if (j is Map && j['estimated_time'] is num) wait = (j['estimated_time'] as num).toDouble();
        } catch (_) {}
        if (attempt == 2) break;
        final seconds = wait.clamp(3, 40).round();
        progress('Model yükleniyor, yaklaşık $seconds sn bekleniyor…', null);
        await Future<void>.delayed(Duration(seconds: seconds));
        if (cancel.isCancelled) throw const OperationCancelled();
        continue;
      }
      break;
    }
    final r = response!;
    _throwForStatus(r, model);
    progress('Sonuç alınıyor…', null);
    final contentType = r.headers['content-type'] ?? '';
    Raster result;
    if (contentType.startsWith('image/')) {
      result = await _decodeResult(r.bodyBytes);
    } else {
      result = await _fromJson(r);
    }
    if (request.task == AiTask.removeBackground) {
      // Maske/kesim düşük çözünürlüklü olabilir: tam çözünürlüklü renklere alfa olarak uygulanır.
      result = await applyAlphaInIsolate(request.image, result);
    }
    return AiResult(image: result, providerName: '$name — $model');
  }

  static Future<Raster> _invert(Raster mask) => Isolate.run(() {
        final inv = mask.clone();
        for (var i = 0; i < inv.rgba.length; i += 4) {
          inv.rgba[i] = 255 - inv.rgba[i];
          inv.rgba[i + 3] = 255;
        }
        return inv;
      });

  Future<Raster> _fromJson(http.Response r) async {
    Object? j;
    try {
      j = jsonDecode(utf8.decode(r.bodyBytes));
    } catch (_) {
      throw const UserFacingException('Sağlayıcıdan beklenmeyen yanıt alındı.');
    }
    // image-segmentation: [{label, score, mask: base64 PNG}]
    if (j is List && j.isNotEmpty) {
      Map? chosen;
      for (final item in j) {
        if (item is Map && item['mask'] is String) {
          final label = '${item['label'] ?? ''}'.toLowerCase();
          if (!label.contains('background')) {
            chosen = item;
            break;
          }
          chosen ??= item;
        }
      }
      if (chosen != null) {
        final mask = await _decodeResult(base64Decode(chosen['mask'] as String));
        if ('${chosen['label'] ?? ''}'.toLowerCase().contains('background')) return _invert(mask);
        return mask;
      }
    }
    if (j is Map && j['image'] is String) {
      return _decodeResult(base64Decode(j['image'] as String));
    }
    throw const UserFacingException('Sağlayıcı yanıtında görsel bulunamadı. Ayarlardan farklı bir model deneyin.');
  }

  void _throwForStatus(http.Response r, String model) {
    if (r.statusCode >= 200 && r.statusCode < 300) return;
    final detail = errorBody(r);
    switch (r.statusCode) {
      case 401:
      case 403:
        throw UserFacingException('Hugging Face erişim anahtarı geçersiz ya da bu modele erişim izni yok ($model).',
            details: detail);
      case 402:
        throw UserFacingException(
            'Hugging Face ücretsiz kredisi tükendi. Ücret oluşturulmadı; kredi yenilenince tekrar deneyin veya yerel yöntemi kullanın.',
            details: detail);
      case 404:
        throw UserFacingException(
            '"$model" modeli bu sağlayıcıda çevrimiçi çalıştırılamıyor. Ayarlar › AI sağlayıcıları bölümünden başka bir model deneyin.',
            details: detail);
      case 413:
        throw UserFacingException('Görsel sağlayıcı için çok büyük.', details: detail);
      case 429:
        throw UserFacingException('İstek sınırına ulaşıldı. Bir süre sonra tekrar deneyin.', details: detail);
      case 503:
        throw UserFacingException('Model şu an kullanılamıyor (yükleniyor veya bakımda). Daha sonra tekrar deneyin.',
            details: detail);
      default:
        throw UserFacingException('Sağlayıcı hata döndürdü (HTTP ${r.statusCode})${detail != null ? ': $detail' : '.'}',
            details: detail);
    }
  }
}

/// remove.bg API adaptörü (yalnızca arka plan kaldırma).
class RemoveBgProvider extends AiProvider with _HttpSupport {
  RemoveBgProvider({required this.apiKey, this.fullResolution = false, HttpClientFactory? clientFactory})
      : clientFactory = clientFactory ?? http.Client.new;

  final String? apiKey;

  /// false: ücretsiz "preview" boyutu (en fazla ~0,25 MP). true: kredi harcar.
  final bool fullResolution;

  @override
  final HttpClientFactory clientFactory;

  @override
  String get id => 'removebg';

  @override
  String get name => 'remove.bg (çevrimiçi)';

  @override
  bool get isOnline => true;

  @override
  bool get isConfigured => (apiKey ?? '').trim().isNotEmpty;

  @override
  String get configurationHint => 'Ayarlar › AI sağlayıcıları bölümüne remove.bg API anahtarınızı girin (remove.bg › Dashboard › API Keys).';

  @override
  Set<AiTask> get supportedTasks => const {AiTask.removeBackground};

  @override
  ProviderPrivacy get privacy => ProviderPrivacy(
        host: 'api.remove.bg',
        dataHandling:
            'Görsel arka plan kaldırma için remove.bg (Kaleido/Canva) sunucularına gönderilir. Saklama süresi ve '
            'kullanım koşulları sağlayıcının gizlilik politikasında açıklanır; PIXELSHIFT bu bilgiyi doğrulayamaz.',
        policyUrl: 'https://www.remove.bg/privacy',
        limits: fullResolution
            ? 'TAM ÇÖZÜNÜRLÜK açık: her işlem hesabınızdan kredi düşer. Krediniz yoksa istek reddedilir.'
            : 'Önizleme boyutu (en fazla ~0,25 MP) kullanılır; ücretsiz hesaplarda aylık sınırlı sayıda ücretsiz '
                'istek hakkı vardır. Maske, tam çözünürlüklü fotoğrafınıza cihazda uygulanır.',
      );

  @override
  Future<AiResult> run(AiRequest request, {required ProgressCallback progress, required CancelToken cancel}) async {
    if (!isConfigured) throw UserFacingException(configurationHint);
    progress('Görsel hazırlanıyor…', null);
    final upload = await UploadImage.prepare(request.image, fullResolution ? 4000 : 1200);
    if (cancel.isCancelled) throw const OperationCancelled();
    final req = http.MultipartRequest('POST', Uri.parse('https://api.remove.bg/v1.0/removebg'))
      ..headers['X-Api-Key'] = apiKey!.trim()
      ..fields['size'] = fullResolution ? 'auto' : 'preview'
      ..fields['format'] = 'png'
      ..files.add(http.MultipartFile.fromBytes('image_file', upload.bytes,
          filename: upload.mimeType == 'image/png' ? 'gorsel.png' : 'gorsel.jpg'));
    progress('Yükleniyor ve işleniyor (remove.bg)…', null);
    final r = await send(req, cancel);
    if (r.statusCode != 200) {
      final detail = errorBody(r);
      throw UserFacingException(
        switch (r.statusCode) {
          400 => 'remove.bg görseli işleyemedi${detail != null ? ': $detail' : '.'}',
          402 => 'remove.bg krediniz yetersiz. Ücret oluşturulmadı.',
          403 => 'remove.bg API anahtarı geçersiz.',
          429 => 'remove.bg istek sınırına ulaşıldı. Daha sonra tekrar deneyin.',
          _ => 'remove.bg hata döndürdü (HTTP ${r.statusCode}).',
        },
        details: detail,
      );
    }
    progress('Maske uygulanıyor…', null);
    final cutout = await _decodeResult(r.bodyBytes);
    final result = await applyAlphaInIsolate(request.image, cutout);
    return AiResult(image: result, providerName: name);
  }
}
