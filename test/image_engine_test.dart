import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pixelshift/core/errors.dart';
import 'package:pixelshift/filters/adjustments.dart';
import 'package:pixelshift/filters/filter_presets.dart';
import 'package:pixelshift/image_engine/codec.dart';
import 'package:pixelshift/image_engine/color_matrix.dart';
import 'package:pixelshift/image_engine/engine.dart';
import 'package:pixelshift/image_engine/geometry.dart';
import 'package:pixelshift/image_engine/ops.dart';
import 'package:pixelshift/image_engine/raster.dart';
import 'package:pixelshift/image_engine/webp_encoder.dart';

import 'helpers.dart';

void main() {
  group('WebP (VP8L) kodlayıcı', () {
    test('gradyan + yarı saydam daire birebir çözülür', () {
      final src = syntheticImage(257, 131);
      final bytes = WebpEncoder.encode(src);
      final back = ImageCodec.decode(bytes, 'a.webp');
      expect(meanAbsDiff(src, back), 0);
    });

    test('rastgele gürültü (alfa dahil) birebir çözülür', () {
      final src = noiseImage(73, 41, seed: 7);
      expect(meanAbsDiff(src, ImageCodec.decode(WebpEncoder.encode(src), 'n.webp')), 0);
    });

    test('kenar durumları: 1x1, tek renk, tamamen şeffaf, ince şerit', () {
      for (final r in [
        Raster.filled(1, 1, 10, 20, 30),
        Raster.filled(64, 48, 200, 100, 50),
        Raster.filled(20, 7, 0, 0, 0, 0),
        syntheticImage(1, 300),
        syntheticImage(300, 1),
      ]) {
        final back = ImageCodec.decode(WebpEncoder.encode(r), 'x.webp');
        expect(meanAbsDiff(r, back), 0, reason: '${r.width}x${r.height}');
      }
    });

    test('`image` paketinin bağımsız çözücüsüyle de doğrulanır', () {
      final src = syntheticImage(120, 90);
      final decoded = img.decodeWebP(WebpEncoder.encode(src))!;
      expect(decoded.width, 120);
      final px = decoded.getPixel(60, 45);
      final i = (45 * 120 + 60) * 4;
      expect([px.r.toInt(), px.g.toInt(), px.b.toInt(), px.a.toInt()], src.rgba.sublist(i, i + 4));
    });

    test('düz görüntüler PNG\'den küçük', () {
      final flat = Raster.filled(512, 512, 30, 60, 90);
      final webp = WebpEncoder.encode(flat);
      final png = ImageCodec.encode(flat, ExportFormat.png);
      expect(webp.length, lessThan(png.length));
    });
  });

  group('Kodlama / çözme', () {
    final src = syntheticImage(160, 120);
    for (final f in ExportFormat.values) {
      test('${f.label} gidiş-dönüş', () {
        final bytes = ImageEngine.encodeSync(src, f, 95);
        final back = ImageCodec.decode(bytes, 'x.${f.extension}');
        expect(back.width, 160);
        expect(back.height, 120);
        if (f.supportsTransparency && f != ExportFormat.webp) expect(meanAbsDiff(src, back), 0);
        if (!f.supportsTransparency) expect(back.hasTransparency, isFalse);
      });
    }

    test('kayıplı WEBP kalite ile boyut değişir', () {
      final big = syntheticImage(400, 300);
      final q40 = ImageEngine.encodeSync(big, ExportFormat.webp, 40);
      final q95 = ImageEngine.encodeSync(big, ExportFormat.webp, 95);
      expect(q40.length, lessThan(q95.length));
      expect(ImageCodec.decode(q40, 'q.webp').width, 400);
    });

    test('tür tespiti sihirli baytlarla yapılır, uzantıya güvenilmez', () {
      final png = ImageCodec.encode(src, ExportFormat.png);
      expect(ImageCodec.detect(png, 'yanlis_uzanti.jpg'), ImageKind.png);
      expect(ImageCodec.decode(png, 'yanlis_uzanti.jpg').width, 160);
    });

    test('bozuk, boş ve desteklenmeyen dosyalar Türkçe hata verir', () {
      final png = ImageCodec.encode(src, ExportFormat.png);
      expect(() => ImageCodec.decode(Uint8List.fromList(png.sublist(0, 60)), 'b.png'), throwsA(isA<UserFacingException>()));
      expect(() => ImageCodec.decode(Uint8List(0), 'b.png'), throwsA(isA<UserFacingException>()));
      expect(() => ImageCodec.decode(Uint8List.fromList('selam'.codeUnits), 'b.txt'), throwsA(isA<UserFacingException>()));
      final heic = Uint8List.fromList([0, 0, 0, 24, ...'ftypheic'.codeUnits, 0, 0, 0, 0]);
      expect(ImageCodec.detect(heic, 'a.heic'), ImageKind.heic);
      expect(() => ImageCodec.decode(heic, 'a.heic'), throwsA(isA<UserFacingException>()));
    });

    test('JPEG önizlemesi ölçekli çözülür, tam boyut doğru raporlanır', () {
      final big = syntheticImage(3000, 2000);
      final jpg = ImageCodec.encode(big, ExportFormat.jpg, quality: 80);
      final (preview, w, h) = ImageCodec.decodePreview(jpg, 'b.jpg', 800);
      expect((w, h), (3000, 2000));
      expect(preview.longSide, lessThanOrEqualTo(800));
    });

    test('RAW: gömülü JPEG önizleme bulunur', () {
      final jpg = ImageCodec.encode(syntheticImage(320, 200), ExportFormat.jpg, quality: 85);
      final fakeRaw = Uint8List.fromList([0x49, 0x49, 0x2a, 0x00, ...List.filled(500, 7), ...jpg, ...List.filled(100, 1)]);
      expect(ImageCodec.detect(fakeRaw, 'foto.nef'), ImageKind.raw);
      expect(ImageCodec.decode(fakeRaw, 'foto.nef').width, 320);
    });
  });

  group('Geometri', () {
    final src = syntheticImage(200, 100);

    test('90° döndürmeler ve çevirme köşe piksellerini doğru taşır', () {
      final r1 = Ops.orient(src, 1);
      expect((r1.width, r1.height), (100, 200));
      // Saat yönünde: kaynağın sol-alt köşesi hedefin sol-üstüne gelir.
      int px(Raster r, int x, int y) => (r.rgba[(y * r.width + x) * 4] << 16) | (r.rgba[(y * r.width + x) * 4 + 1] << 8);
      expect(px(r1, 0, 0), px(src, 0, 99));
      final r4 = Ops.orient(Ops.orient(Ops.orient(r1, 1), 1), 1);
      expect(meanAbsDiff(r4, src), 0);
      final f = Ops.orient(src, 0, flipH: true);
      expect(px(f, 0, 0), px(src, 199, 0));
    });

    test('kırpma ve düzleştirme boyutları', () {
      final c = Ops.applyGeometry(src, const Geometry(crop: NormRect(0.1, 0.2, 0.6, 0.7)));
      expect((c.width, c.height), (100, 50));
      final g = const Geometry(straighten: 12, crop: NormRect(0, 0, 0.5, 1));
      final out = Ops.applyGeometry(src, g);
      expect((out.width, out.height), g.outputSize(200, 100));
    });

    test('JSON gidiş-dönüş', () {
      const g = Geometry(quarterTurns: 3, flipH: true, straighten: -7.5, crop: NormRect(0.1, 0.1, 0.9, 0.8));
      expect(Geometry.fromJson(g.toJson()), g);
    });
  });

  group('Renk ve ayarlar', () {
    test('birim matris pikselleri değiştirmez', () {
      final r = syntheticImage(32, 32);
      final copy = r.clone();
      ColorMatrix.identity().applyTo(r);
      expect(meanAbsDiff(r, copy), 0);
    });

    test('nötr ayar birim matristir; her filtre geçerli matris üretir', () {
      expect(Adjustments.none.colorMatrix().isIdentity, isTrue);
      for (final f in FilterPresets.all) {
        expect(Adjustments(filterId: f.id).colorMatrix().values.length, 20);
      }
    });

    test('compose sırası: önce iç matris uygulanır', () {
      final add = ColorMatrix.offset(10, 10, 10);
      final dbl = ColorMatrix.scale(2, 2, 2);
      final r = Raster.filled(1, 1, 10, 10, 10);
      dbl.compose(add).applyTo(r); // (10 + 10) * 2
      expect(r.rgba[0], 40);
    });

    test('ayarlar JSON gidiş-dönüş', () {
      const a = Adjustments(exposure: 12, contrast: -5, grayscale: true, sharpness: 40, filterId: 'vintage', filterIntensity: 70);
      expect(Adjustments.fromJson(a.toJson()), a);
    });

    test('detay işlemleri girdiyi değiştirmez', () {
      final r = syntheticImage(64, 64);
      final copy = r.clone();
      ImageEngine.applyDetail(r, const Adjustments(sharpness: 80, vignette: -50, grain: 30, shadows: 40));
      expect(meanAbsDiff(r, copy), 0);
    });
  });

  group('Boyutlandırma', () {
    test('alan ortalaması ile küçültme ve bikübik büyütme', () {
      final r = Raster.filled(100, 100, 120, 130, 140);
      final s = Ops.resize(r, 33, 17);
      expect((s.width, s.height), (33, 17));
      expect(s.rgba[0], 120);
      final b = Ops.resize(r, 250, 250);
      expect(b.rgba[(125 * 250 + 125) * 4 + 1], 130);
    });

    test('fitWithin uzun kenarı sınırlar', () {
      final r = Ops.fitWithin(syntheticImage(1000, 400), 250);
      expect((r.width, r.height), (250, 100));
    });
  });
}
