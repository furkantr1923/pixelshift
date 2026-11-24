import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pixelshift/app/app.dart';
import 'package:pixelshift/app/services.dart';
import 'package:pixelshift/app/unsaved_guard.dart';
import 'package:pixelshift/core/app_info.dart';
import 'package:pixelshift/editor/editor_controller.dart';
import 'package:pixelshift/editor/editor_page.dart';
import 'package:pixelshift/platform_services/app_paths.dart';
import 'package:pixelshift/platform_services/file_service.dart';
import 'package:pixelshift/projects/project_factory.dart';
import 'package:pixelshift/image_engine/codec.dart';
import 'package:pixelshift/settings/about_page.dart';
import 'package:pixelshift/settings/settings_page.dart';
import 'package:pixelshift/templates/templates_page.dart';

import 'helpers.dart';

/// Arayüz testleri. Veritabanı ve isolate işleri gerçek zamanlıdır;
/// `runAsync` ile beklenir. Hem masaüstü hem telefon boyutunda taşma
/// (overflow) olmadığı doğrulanır.
void main() {
  setUpAll(ensureFfi);

  Future<AppServices> services(WidgetTester tester) async {
    return (await tester.runAsync(() async {
      final dir = await tempDir('pixelshift_widget_');
      return AppServices.create(paths: AppPaths(root: dir.path));
    }))!;
  }

  Future<void> settle(WidgetTester tester, [int ms = 400]) async {
    await tester.runAsync(() => Future<void>.delayed(Duration(milliseconds: ms)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
  }

  void setSize(WidgetTester tester, Size logical, {double dpr = 1}) {
    tester.view.devicePixelRatio = dpr;
    tester.view.physicalSize = logical * dpr;
    addTearDown(tester.view.reset);
  }

  for (final (name, size, dpr) in [('masaüstü', const Size(1440, 900), 1.0), ('telefon', const Size(390, 844), 3.0)]) {
    testWidgets('ana ekran Türkçe ve taşmasız ($name)', (tester) async {
      setSize(tester, size, dpr: dpr);
      final s = await services(tester);
      await tester.pumpWidget(PixelShiftApp(services: s));
      await settle(tester);
      expect(find.text('PIXELSHIFT'), findsWidgets);
      for (final t in ['Şablonlar', 'Kolaj', 'Boş tuval', 'Toplu işlem', 'Projeler']) {
        expect(find.text(t), findsWidgets, reason: t);
      }
      expect(find.textContaining('Henüz proje yok'), findsOneWidget);
    });

    testWidgets('düzenleyici açılır, araçlar ve geri al çalışır ($name)', (tester) async {
      setSize(tester, size, dpr: dpr);
      final s = await services(tester);
      final created = (await tester.runAsync(() => ProjectFactory(s).fromFile(
            PickedFile('deneme.png', ImageCodec.encode(syntheticImage(640, 400), ExportFormat.png)),
          )))!;
      await tester.pumpWidget(Services(services: s, child: MaterialApp(home: EditorPage(projectId: created.info.id))));
      for (var i = 0; i < 10 && UnsavedGuard.active == null; i++) {
        await settle(tester, 300);
      }
      final c = UnsavedGuard.active!;
      await settle(tester, 600);
      expect(c.baseImage, isNotNull, reason: 'önizleme oluşmalı');
      expect(tester.takeException(), isNull);

      c.addText(text: 'Merhaba Dünya');
      await settle(tester);
      expect(c.doc.layers.length, 1);
      expect(c.isDirty, isTrue);
      c.undo();
      await settle(tester);
      expect(c.doc.layers, isEmpty);
      c.redo();
      await settle(tester);
      expect(c.doc.layers.length, 1);

      for (final tool in [EditorTool.adjust, EditorTool.filters, EditorTool.crop, EditorTool.text, EditorTool.shapes, EditorTool.stickers, EditorTool.mask, EditorTool.ai]) {
        c.setTool(tool);
        await settle(tester, 200);
        expect(tester.takeException(), isNull, reason: tool.label);
      }
      c.cancelCrop();
      c.setTool(EditorTool.select);
      await tester.runAsync(c.save);
      expect(c.isDirty, isFalse);
      await tester.pumpWidget(const SizedBox());
      await settle(tester);
    });
  }

  testWidgets('Hakkında ekranında imza görünür', (tester) async {
    final s = await services(tester);
    await tester.pumpWidget(Services(services: s, child: const MaterialApp(home: AboutPage())));
    await tester.pumpAndSettle();
    expect(find.text(AppInfo.signature), findsOneWidget);
    expect(AppInfo.signature, 'PIXELSHIFT — Furkan tarafından geliştirildi.');
  });

  testWidgets('Ayarlar ve şablonlar açılır', (tester) async {
    setSize(tester, const Size(1280, 900));
    final s = await services(tester);
    await tester.pumpWidget(Services(services: s, child: const MaterialApp(home: SettingsPage())));
    await tester.pumpAndSettle();
    expect(find.text('AI sağlayıcıları'), findsOneWidget);
    expect(find.textContaining('kaynak koda gömülmez'), findsOneWidget);
    await tester.pumpWidget(Services(services: s, child: const MaterialApp(home: TemplatesPage())));
    await tester.pumpAndSettle();
    expect(find.text('Etkinlik afişi'), findsOneWidget);
  });

  test('kaynak kodunda gömülü API anahtarı yok', () {
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      final text = f.readAsStringSync();
      if (RegExp(r'hf_[A-Za-z0-9]{20,}').hasMatch(text) || RegExp(r"X-Api-Key'\]\s*=\s*'[A-Za-z0-9]{10,}").hasMatch(text)) {
        offenders.add(f.path);
      }
    }
    expect(offenders, isEmpty);
  });

  test('arayüz metinlerinde İngilizce düğme/başlık kalmadı', () {
    final english = RegExp(r"""Text\('(Save|Cancel|Open|Delete|Settings|Export|Undo|Redo|Loading|Error|Close|Apply)['.…]""");
    final offenders = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (english.hasMatch(f.readAsStringSync())) offenders.add(f.path);
    }
    expect(offenders, isEmpty);
  });
}
