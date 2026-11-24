import 'package:flutter_test/flutter_test.dart';
import 'package:pixelshift/batch_processing/batch_service.dart';
import 'package:pixelshift/core/errors.dart';
import 'package:pixelshift/filters/adjustments.dart';
import 'package:pixelshift/image_engine/classic.dart';
import 'package:pixelshift/image_engine/codec.dart';
import 'package:pixelshift/image_engine/raster.dart';

import 'helpers.dart';

Raster studio() {
  final r = Raster.filled(200, 150, 240, 240, 242);
  for (var y = 40; y < 110; y++) {
    for (var x = 70; x < 130; x++) {
      final j = (y * 200 + x) * 4;
      r.rgba[j] = 30;
      r.rgba[j + 1] = 90;
      r.rgba[j + 2] = 200;
    }
  }
  return r;
}

void main() {
  test('nesne silme: maskeli alan çevreden doldurulur', () {
    final r = Raster.filled(120, 80, 50, 120, 200);
    // ortada kırmızı "nesne"
    for (var y = 30; y < 50; y++) {
      for (var x = 50; x < 70; x++) {
        r.rgba[(y * 120 + x) * 4] = 255;
        r.rgba[(y * 120 + x) * 4 + 1] = 0;
      }
    }
    final mask = Classic.rasterizeStrokes(120, 80, [
      [14, 60, 40],
    ]);
    final out = Classic.inpaint(r, mask);
    final c = (40 * 120 + 60) * 4;
    expect((out.rgba[c] - 50).abs(), lessThan(25), reason: 'kırmızı nesne kalkmalı');
    expect((out.rgba[c + 2] - 200).abs(), lessThan(25));
  });

  test('nesne silme: boş maske ve çok büyük alan reddedilir', () {
    final r = syntheticImage(50, 50);
    expect(() => Classic.inpaint(r, Classic.rasterizeStrokes(50, 50, const [])), throwsA(isA<UserFacingException>()));
    expect(
      () => Classic.inpaint(r, Classic.rasterizeStrokes(50, 50, [
        [60, 25, 25],
      ])),
      throwsA(isA<UserFacingException>()),
    );
  });

  test('düz arka plan kaldırma ve arka plan değiştirme', () {
    final cut = Classic.removeUniformBackground(studio());
    expect(cut.rgba[3], 0);
    expect(cut.rgba[(75 * 200 + 100) * 4 + 3], 255);
    final replaced = Classic.replaceBackground(cut, topArgb: 0xFFFF0000, bottomArgb: 0xFFFF0000);
    expect(replaced.rgba[0], 255);
    expect(replaced.rgba[3], 255);
    expect(replaced.rgba[(75 * 200 + 100) * 4 + 2], 200);
  });

  test('karmaşık arka planda yerel yöntem dürüstçe reddeder', () {
    expect(() => Classic.removeUniformBackground(noiseImage(80, 60, alpha: false)), throwsA(isA<UserFacingException>()));
  });

  test('şeffaflık yokken arka plan değiştirme açıklama ister', () {
    expect(() => Classic.replaceBackground(Raster.filled(10, 10, 1, 2, 3)), throwsA(isA<UserFacingException>()));
  });

  test('büyütme, iyileştirme, portre, restorasyon ve stiller çalışır', () {
    final src = syntheticImage(90, 60);
    expect(Classic.upscale(src, 2).width, 180);
    expect(Classic.upscale(src, 4).height, 240);
    for (final r in [Classic.enhance(src), Classic.portrait(src), Classic.restore(src), Classic.skinSmooth(src, 0.6)]) {
      expect((r.width, r.height), (90, 60));
    }
    for (final s in Classic.styleNames.keys) {
      expect(Classic.style(src, s).width, 90, reason: s);
    }
  });

  test('otomatik ayar karanlık görüntüyü aydınlatır', () {
    final dark = Raster.filled(64, 64, 25, 25, 30);
    for (var i = 0; i < dark.rgba.length; i += 16) {
      dark.rgba[i] = 60;
    }
    final a = Classic.suggestAdjustments(dark, Adjustments.none);
    expect(a.exposure, greaterThan(0));
  });

  test('toplu işlem: boyutlandırma + format + ad', () {
    final bytes = ImageCodec.encode(syntheticImage(400, 200), ExportFormat.png);
    final out = BatchService.processSync(
      bytes,
      'tatil.png',
      const BatchOptions(format: ExportFormat.webp, quality: 80, resizeMode: ResizeMode.maxSide, maxSide: 100, filterId: 'bw'),
    );
    expect(out.fileName, 'tatil_pixelshift.webp');
    expect((out.width, out.height), (100, 50));
    final back = ImageCodec.decode(out.bytes, out.fileName);
    final i = (25 * 100 + 50) * 4;
    expect((back.rgba[i] - back.rgba[i + 1]).abs(), lessThan(8), reason: 'siyah-beyaz filtre');
  });

  test('toplu işlem: bozuk dosya hatası diğerlerini etkilemez', () {
    expect(() => BatchService.processSync(ImageCodec.encode(syntheticImage(10, 10), ExportFormat.png).sublist(0, 30), 'b.png', const BatchOptions()),
        throwsA(isA<UserFacingException>()));
  });
}
