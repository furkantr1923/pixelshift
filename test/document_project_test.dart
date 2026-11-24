import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:pixelshift/core/errors.dart';
import 'package:pixelshift/editor/document.dart';
import 'package:pixelshift/editor/history.dart';
import 'package:pixelshift/filters/adjustments.dart';
import 'package:pixelshift/image_engine/codec.dart';
import 'package:pixelshift/image_engine/geometry.dart';
import 'package:pixelshift/layers/layer.dart';
import 'package:pixelshift/projects/project_database.dart';
import 'package:pixelshift/projects/project_store.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'helpers.dart';

EditDocument sampleDoc() => const EditDocument(
      sourceFile: 'source.png',
      sourceWidth: 800,
      sourceHeight: 600,
      geometry: Geometry(quarterTurns: 1, crop: NormRect(0.1, 0.1, 0.9, 0.9)),
      adjustments: Adjustments(exposure: 10, filterId: 'film'),
      layers: [
        TextLayer(
          id: 't',
          name: 'Başlık',
          cx: 100,
          cy: 50,
          text: 'Çığ ışığı ÖĞÜŞ',
          fontFamily: 'Anton',
          strokeWidth: 3,
          background: 0x80000000,
          blend: LayerBlend.overlay,
          mask: [MaskStroke(points: [0, 0, 10, 10], radius: 5)],
        ),
        ImageLayer(
          id: 'i',
          name: 'Logo',
          cx: 200,
          cy: 200,
          assetFile: 'a_1.png',
          assetWidth: 64,
          assetHeight: 64,
          width: 120,
          height: 120,
          cornerRadius: 12,
          contentScale: 1.5,
          opacity: 0.5,
        ),
        ShapeLayer(id: 's', name: 'Yıldız', cx: 10, cy: 20, shape: ShapeKind.star, width: 50, height: 50, rotation: 0.5),
      ],
    );

void main() {
  setUpAll(ensureFfi);

  test('belge JSON gidiş-dönüşü tüm katman türlerini korur', () {
    final d = sampleDoc();
    final json = jsonDecode(jsonEncode(d.toJson())) as Map<String, Object?>;
    final back = EditDocument.fromJson(json);
    expect(jsonEncode(back.toJson()), jsonEncode(d.toJson()));
    expect(back.layers.map((l) => l.type), [LayerType.text, LayerType.image, LayerType.shape]);
    expect((back.layers.first as TextLayer).text, 'Çığ ışığı ÖĞÜŞ');
    expect(back.layers.first.mask.single.radius, 5);
  });

  test('tuval boyutu geometriye göre hesaplanır (döndürme + kırpma)', () {
    final d = sampleDoc();
    expect(d.canvasSize, (480, 640));
  });

  test('katman sırası işlemleri', () {
    final d = sampleDoc();
    expect(d.moveLayer('t', 1).layers.map((l) => l.id), ['i', 't', 's']);
    expect(d.reorderLayer(2, 0).layers.map((l) => l.id), ['s', 't', 'i']);
    expect(d.removeLayer('i').layers.length, 2);
  });

  test('geçmiş: geri al / yinele / dal kesme / sınır', () {
    final h = History<int>(0, limit: 4);
    h.push(1, 'a');
    h.push(2, 'b');
    expect(h.undo(), 1);
    h.push(3, 'c'); // yinelenebilir dal silinir
    expect(h.canRedo, isFalse);
    expect(h.items, [0, 1, 3]);
    h.push(4, 'd');
    h.push(5, 'e');
    expect(h.length, 4);
    expect(h.items.first, 1);
    expect(h.undoLabel, 'e');
  });

  group('Proje deposu (gerçek SQLite + dosya sistemi)', () {
    late Directory dir;
    late ProjectStore store;
    late ProjectDatabase db;

    setUp(() async {
      dir = await tempDir('pixelshift_store_');
      db = await ProjectDatabase.open(p.join(dir.path, 'db.sqlite'), factory: databaseFactoryFfi);
      store = ProjectStore(projectsDir: p.join(dir.path, 'Projeler'), database: db);
    });

    tearDown(() async {
      await db.close();
      await dir.delete(recursive: true);
    });

    Future<ProjectInfo> create() => store.create(
          name: 'Tatil',
          sourceBytes: ImageCodec.encode(syntheticImage(80, 60), ExportFormat.png),
          sourceExtension: 'png',
          width: 80,
          height: 60,
          documentBuilder: (f) => EditDocument(sourceFile: f, sourceWidth: 80, sourceHeight: 60),
        );

    test('oluştur, kaydet, yeniden aç, yeniden adlandır, sil', () async {
      final info = await create();
      final data = await store.load(info.id);
      final d1 = data.current.copyWith(adjustments: const Adjustments(contrast: 30));
      await store.save(data.info, [data.current, d1], ['Açılış', 'Kontrast'], 1);
      final again = await store.load(info.id);
      expect(again.history.length, 2);
      expect(again.current.adjustments.contrast, 30);
      expect(again.labels, ['Açılış', 'Kontrast']);
      await store.rename(again.info, 'Yaz tatili');
      expect((await store.list()).single.name, 'Yaz tatili');
      await store.delete(info.id);
      expect(await store.list(), isEmpty);
    });

    test('kullanılmayan türetilmiş kaynaklar ve katman görselleri temizlenir', () async {
      final info = await create();
      final v = await store.addSourceVersion(info.id, ImageCodec.encode(syntheticImage(10, 10), ExportFormat.png), 'png');
      final a = await store.addAsset(info.id, ImageCodec.encode(syntheticImage(10, 10), ExportFormat.png), 'png');
      final data = await store.load(info.id);
      await store.save(data.info, [data.current], ['Açılış'], 0);
      expect(await File(store.fileOf(info.id, v)).exists(), isFalse);
      expect(await File(store.assetPath(info.id, a)).exists(), isFalse);
      expect(await File(store.fileOf(info.id, 'source.png')).exists(), isTrue, reason: 'orijinal asla silinmez');
    });

    test('bozuk proje dosyası anlaşılır hata verir', () async {
      final info = await create();
      await File(store.fileOf(info.id, 'project.json')).writeAsString('{bozuk');
      expect(() => store.load(info.id), throwsA(isA<UserFacingException>()));
    });

    test('dizin kaydı olmayan proje klasörü listeye alınır', () async {
      final info = await create();
      await db.delete(info.id);
      final list = await store.list();
      expect(list.map((e) => e.id), [info.id]);
    });

    test('geçmiş sınırı aşıldığında güncel adım korunur', () async {
      final info = await create();
      final data = await store.load(info.id);
      final docs = [for (var i = 0; i < 60; i++) data.current.copyWith(adjustments: Adjustments(exposure: i.toDouble()))];
      await store.save(data.info, docs, [for (var i = 0; i < 60; i++) 'adım $i'], 59);
      final again = await store.load(info.id);
      expect(again.history.length, ProjectStore.savedHistoryLimit);
      expect(again.current.adjustments.exposure, 59);
    });
  });
}
