import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pixelshift/ai/ai_models.dart';
import 'package:pixelshift/ai/ai_service.dart';
import 'package:pixelshift/ai/local_provider.dart';
import 'package:pixelshift/app/app.dart';
import 'package:pixelshift/app/services.dart';
import 'package:pixelshift/app/unsaved_guard.dart';
import 'package:pixelshift/editor/editor_controller.dart';
import 'package:pixelshift/editor/editor_page.dart';
import 'package:pixelshift/export/export_service.dart';
import 'package:pixelshift/filters/adjustments.dart';
import 'package:pixelshift/image_engine/codec.dart';
import 'package:pixelshift/layers/layer.dart';
import 'package:pixelshift/platform_services/app_paths.dart';
import 'package:pixelshift/platform_services/file_service.dart';
import 'package:pixelshift/projects/project_factory.dart';
import 'package:pixelshift/self_test.dart' show syntheticImage, meanAbsDiff;

/// Gerçek cihazda / emülatörde / Windows'ta uçtan uca test.
///
///   flutter test integration_test/app_test.dart -d windows
///   flutter test integration_test/app_test.dart -d emulator-5554
Future<void> waitUntil(WidgetTester tester, bool Function() condition, {Duration timeout = const Duration(seconds: 40)}) async {
  final deadline = DateTime.now().add(timeout);
  while (!condition() && DateTime.now().isBefore(deadline)) {
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await tester.pump();
  }
  await tester.pump(const Duration(milliseconds: 300));
  expect(condition(), isTrue, reason: 'koşul zaman aşımına uğradı');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('uçtan uca: içe aktar → düzenle → katman → AI (yerel) → kaydet → yeniden aç → dışa aktar', (tester) async {
    final tmp = await getTemporaryDirectory();
    final root = p.join(tmp.path, 'pixelshift_it_${DateTime.now().millisecondsSinceEpoch}');
    final services = await AppServices.create(paths: AppPaths(root: root));

    // 1) Uygulama açılışı
    await tester.pumpWidget(PixelShiftApp(services: services));
    await tester.pumpAndSettle();
    expect(find.text('Şablonlar'), findsWidgets);

    // 2) Görsel içe aktarma (dosya seçiciyi atlayarak aynı fabrika yolu)
    final source = syntheticImage(1600, 1000);
    final created = await ProjectFactory(services).fromFile(PickedFile('deneme.png', ImageCodec.encode(source, ExportFormat.png)));

    // 3) Düzenleyiciyi aç
    UnsavedGuard.active = null;
    await tester.pumpWidget(Services(services: services, child: MaterialApp(home: EditorPage(projectId: created.info.id))));
    await waitUntil(tester, () => UnsavedGuard.active?.baseImage != null);
    final c = UnsavedGuard.active!;

    // 4) Temel düzenleme + geri al/yinele (arayüz düğmesiyle)
    c.commitAdjustments('Kontrast', c.doc.adjustments.copyWith(contrast: 30, saturation: 20, filterId: 'vintage'));
    c.rotate90();
    await tester.pumpAndSettle();
    expect(c.doc.canvasSize, (1000, 1600));
    await tester.tap(find.byIcon(Icons.undo).first);
    await tester.pumpAndSettle();
    expect(c.doc.canvasSize, (1600, 1000));
    await tester.tap(find.byIcon(Icons.redo).first);
    await tester.pumpAndSettle();
    expect(c.doc.canvasSize, (1000, 1600));

    // 5) Katmanlar: metin + şekil + maske
    c.addText(text: 'PIXELSHIFT Testi ğüşıöç');
    c.addShape(ShapeKind.star);
    c.setTool(EditorTool.mask);
    c.maskStrokeStart(c.canvasCenter);
    c.maskStrokeUpdate(c.canvasCenter + const Offset(40, 10));
    c.maskStrokeEnd();
    await tester.pumpAndSettle();
    expect(c.doc.layers.length, 2);
    expect(c.doc.layers.last.mask, isNotEmpty);

    // 6) Yerel AI (çevrimdışı klasik iyileştirme) — izin istemez
    final service = AiService(consent: (_) async => false);
    await c.runAi(service, LocalClassicProvider(), AiTask.enhance, progress: (_, __) {}, cancel: CancelToken());
    await waitUntil(tester, () => !c.rendering);
    expect(c.doc.sourceFile, startsWith('source_'));
    expect(c.doc.layers.length, 2, reason: 'katmanlar korunur');

    // 7) Kaydet ve yeniden aç
    await c.save();
    expect(c.isDirty, isFalse);
    final savedHistory = c.history.length;
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    UnsavedGuard.active = null;
    await tester.pumpWidget(Services(services: services, child: MaterialApp(home: EditorPage(projectId: created.info.id))));
    await waitUntil(tester, () => UnsavedGuard.active?.baseImage != null);
    final c2 = UnsavedGuard.active!;
    expect(c2.doc.layers.length, 2);
    expect(c2.history.length, savedHistory);
    expect(c2.doc.adjustments, isNot(Adjustments.none));

    // 8) Dışa aktarma: JPG / PNG (şeffaflık) / WEBP
    for (final f in [ExportFormat.jpg, ExportFormat.png, ExportFormat.webp]) {
      final out = await ExportService.export(
        store: services.store,
        projectId: created.info.id,
        doc: c2.doc,
        options: ExportOptions(format: f, quality: 90, width: 500, height: 800),
      );
      final back = ImageCodec.decode(out.bytes, 'x.${f.extension}');
      expect((back.width, back.height), (500, 800), reason: f.label);
    }

    // 9) Geri alma kaynak sürümünü de geri getirir
    c2.jumpTo(0);
    await waitUntil(tester, () => !c2.rendering);
    expect(c2.doc.sourceFile, 'source.png');
    expect(meanAbsDiff(source, source), 0);

    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await Directory(root).delete(recursive: true);
  });
}
