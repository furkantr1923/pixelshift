import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pixelshift/ai/ai_models.dart';
import 'package:pixelshift/ai/ai_service.dart';
import 'package:pixelshift/ai/command_parser.dart';
import 'package:pixelshift/ai/local_provider.dart';
import 'package:pixelshift/ai/online_providers.dart';
import 'package:pixelshift/core/errors.dart';
import 'package:pixelshift/filters/adjustments.dart';
import 'package:pixelshift/image_engine/codec.dart';
import 'package:pixelshift/image_engine/geometry.dart';
import 'package:pixelshift/image_engine/raster.dart';

import 'helpers.dart';

Uint8List png(Raster r) => ImageCodec.encode(r, ExportFormat.png);

void main() {
  final image = syntheticImage(96, 64);
  AiRequest req(AiTask t, {Map<String, Object?> params = const {}}) => AiRequest(task: t, image: image, params: params);
  void noop(String _, double? __) {}

  group('Gizlilik: izin', () {
    test('izin verilmezse çevrimiçi sağlayıcıya HİÇ istek gitmez', () async {
      var requests = 0;
      final provider = HuggingFaceProvider(
        token: 'hf_test',
        clientFactory: () => MockClient((r) async {
          requests++;
          return http.Response('', 200);
        }),
      );
      ConsentRequest? shown;
      final service = AiService(consent: (r) async {
        shown = r;
        return false;
      });
      await expectLater(
        service.run(provider, req(AiTask.removeBackground), progress: noop, cancel: CancelToken()),
        throwsA(isA<OperationCancelled>()),
      );
      expect(requests, 0);
      expect(shown!.privacy.host, 'router.huggingface.co');
      expect(shown!.uploadDescription, contains('EXIF'));
    });

    test('yerel sağlayıcı izin istemez ve internet kullanmaz', () async {
      var asked = false;
      final service = AiService(consent: (_) async => asked = true);
      final r = await service.run(LocalClassicProvider(), req(AiTask.enhance), progress: noop, cancel: CancelToken());
      expect(asked, isFalse);
      expect(r.image.width, 96);
    });

    test('yapılandırılmamış sağlayıcı açıklayıcı hata verir', () async {
      final service = AiService(consent: (_) async => true);
      await expectLater(
        service.run(HuggingFaceProvider(token: ''), req(AiTask.upscale), progress: noop, cancel: CancelToken()),
        throwsA(isA<UserFacingException>().having((e) => e.message, 'mesaj', contains('erişim anahtar'))),
      );
    });
  });

  group('Hugging Face adaptörü', () {
    HuggingFaceProvider withServer(Future<http.Response> Function(http.Request) handler) =>
        HuggingFaceProvider(token: 'hf_test', clientFactory: () => MockClient(handler));

    test('başarılı görsel yanıtı + yetki başlığı', () async {
      final out = syntheticImage(192, 128);
      late http.Request seen;
      final p = withServer((r) async {
        seen = r;
        return http.Response.bytes(png(out), 200, headers: {'content-type': 'image/png'});
      });
      final res = await p.run(req(AiTask.upscale), progress: noop, cancel: CancelToken());
      expect(res.image.width, 192);
      expect(seen.headers['Authorization'], 'Bearer hf_test');
      expect(seen.url.toString(), contains('caidas/swin2SR'));
    });

    test('segmentasyon maskesi tam çözünürlüğe alfa olarak uygulanır', () async {
      final mask = Raster.filled(48, 32, 255, 255, 255);
      for (var i = 0; i < 48 * 4; i += 4) {
        mask.rgba[i] = mask.rgba[i + 1] = mask.rgba[i + 2] = 0; // ilk satır arka plan
      }
      final body = jsonEncode([
        {'label': 'foreground', 'score': 1, 'mask': base64Encode(png(mask))},
      ]);
      final p = withServer((_) async => http.Response(body, 200, headers: {'content-type': 'application/json'}));
      final res = await p.run(req(AiTask.removeBackground), progress: noop, cancel: CancelToken());
      expect(res.image.width, 96);
      expect(res.image.rgba[3], 0);
      expect(res.image.rgba[(40 * 96 + 50) * 4 + 3], greaterThan(0));
    });

    test('HTTP hataları Türkçe ve ücret konusunda dürüst', () async {
      for (final (code, text) in [(401, 'geçersiz'), (402, 'Ücret oluşturulmadı'), (404, 'başka bir model'), (429, 'sınır')]) {
        final p = withServer((_) async => http.Response('{"error":"x"}', code));
        await expectLater(
          p.run(req(AiTask.upscale), progress: noop, cancel: CancelToken()),
          throwsA(isA<UserFacingException>().having((e) => e.message, 'mesaj', contains(text))),
          reason: 'HTTP $code',
        );
      }
    });

    test('model yükleniyor (503) yanıtında bekleyip yeniden dener', () async {
      var calls = 0;
      final p = withServer((_) async {
        calls++;
        if (calls == 1) return http.Response('{"error":"loading","estimated_time":0.1}', 503);
        return http.Response.bytes(png(image), 200, headers: {'content-type': 'image/png'});
      });
      final res = await p.run(req(AiTask.upscale), progress: noop, cancel: CancelToken());
      expect(calls, 2);
      expect(res.image.width, 96);
    }, timeout: const Timeout(Duration(seconds: 30)));

    test('internet yokken anlaşılır hata', () async {
      final p = withServer((_) async => throw const SocketException('ağ yok'));
      await expectLater(
        p.run(req(AiTask.upscale), progress: noop, cancel: CancelToken()),
        throwsA(isA<UserFacingException>()),
      );
    });

    test('iptal edilince sonuç kullanılmaz', () async {
      final cancel = CancelToken();
      final p = withServer((_) async {
        cancel.cancel();
        return http.Response.bytes(png(image), 200, headers: {'content-type': 'image/png'});
      });
      await expectLater(p.run(req(AiTask.upscale), progress: noop, cancel: cancel), throwsA(isA<OperationCancelled>()));
    });

    test('metin komutu JSON gövdesiyle gönderilir', () async {
      late Map<String, dynamic> body;
      final p = withServer((r) async {
        body = jsonDecode(r.body) as Map<String, dynamic>;
        return http.Response.bytes(png(image), 200, headers: {'content-type': 'image/png'});
      });
      await p.run(req(AiTask.textEdit, params: {'prompt': 'make it snowy'}), progress: noop, cancel: CancelToken());
      expect(body['parameters'], {'prompt': 'make it snowy'});
      expect(base64Decode(body['inputs'] as String).length, greaterThan(100));
    });
  });

  group('remove.bg adaptörü', () {
    test('402: kredi yetersiz, ücret oluşmadı', () async {
      final p = RemoveBgProvider(apiKey: 'k', clientFactory: () => MockClient((_) async => http.Response('{}', 402)));
      await expectLater(
        p.run(req(AiTask.removeBackground), progress: noop, cancel: CancelToken()),
        throwsA(isA<UserFacingException>().having((e) => e.message, 'mesaj', contains('Ücret oluşturulmadı'))),
      );
    });

    test('varsayılan olarak ücretsiz önizleme boyutu istenir', () async {
      String? size;
      final cutout = syntheticImage(48, 32);
      final p = RemoveBgProvider(
        apiKey: 'k',
        clientFactory: () => MockClient.streaming((request, stream) async {
          final bytes = await stream.toBytes();
          size = utf8.decode(bytes, allowMalformed: true).contains('preview') ? 'preview' : 'other';
          return http.StreamedResponse(Stream.value(png(cutout)), 200, headers: {'content-type': 'image/png'});
        }),
      );
      final res = await p.run(req(AiTask.removeBackground), progress: noop, cancel: CancelToken());
      expect(size, 'preview');
      expect(res.image.width, 96, reason: 'maske tam çözünürlüğe uygulanır');
    });
  });

  group('Yerel komut yorumlayıcı', () {
    CommandResult parse(String s) => CommandParser.parse(s, Adjustments.none, Geometry.identity);

    test('Türkçe komutlar', () {
      expect(parse('daha parlak yap').adjustments.exposure, greaterThan(0));
      expect(parse('biraz karart').adjustments.exposure, lessThan(0));
      expect(parse('kontrastı çok artır').adjustments.contrast, 40);
      expect(parse('kontrastı azalt').adjustments.contrast, lessThan(0));
      expect(parse('SİYAH BEYAZ').adjustments.grayscale, isTrue);
      expect(parse('sıcak tonlar ve canlı renkler').adjustments.temperature, greaterThan(0));
      expect(parse('sıcak tonlar ve canlı renkler').adjustments.saturation, greaterThan(0));
      expect(parse('vintage filtre uygula').adjustments.filterId, 'vintage');
      expect(parse('sağa döndür').geometry.quarterTurns, 1);
      expect(parse('sola döndür').geometry.quarterTurns, 3);
      expect(parse('gökyüzüne bulut ekle').isEmpty, isTrue);
    });
  });
}
