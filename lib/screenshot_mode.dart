import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'app/app.dart';
import 'app/services.dart';
import 'app/unsaved_guard.dart';
import 'collage/collage_layouts.dart';
import 'core/ids.dart';
import 'editor/editor_controller.dart';
import 'editor/editor_page.dart';
import 'layers/layer.dart';
import 'platform_services/app_paths.dart';
import 'platform_services/file_service.dart';
import 'platform_services/ui_images.dart';
import 'projects/project_factory.dart';
import 'templates/templates.dart';

/// `pixelshift.exe --screenshots=<klasör>`: gerçek arayüzün ekran
/// görüntülerini üretir (README ve sunum için). Geçici veri klasörü kullanır;
/// kullanıcının projelerine dokunmaz.
Future<void> runScreenshotMode(String outDir) async {
  await Directory(outDir).create(recursive: true);
  final log = <String>[];
  final temp = await Directory.systemTemp.createTemp('pixelshift_shots_');
  try {
    final services = await AppServices.create(paths: AppPaths(root: temp.path));
    final factory = ProjectFactory(services);

    Future<PickedFile> asset(String name, String label) async {
      final data = await rootBundle.load('assets/demo/$name');
      return PickedFile(label, data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    }

    // Örnek projeler (CC0 fotoğraflar + şablon + kolaj)
    final coffee = await factory.fromFile(await asset('kahve.jpg', 'Kahve molası.jpg'));
    await factory.fromFile(await asset('roket.jpg', 'Fırlatma.jpg'));
    await factory.fromTemplate(DesignTemplate.all.first);
    await factory.collage(
      layout: CollageLayout.all[2],
      width: 2048,
      height: 2048,
      spacing: 24,
      radius: 18,
      background: 0xFFFFFFFF,
      photos: [await asset('kahve.jpg', 'kahve.jpg'), await asset('kedi.jpg', 'kedi.jpg'), await asset('roket.jpg', 'roket.jpg')],
    );

    // Küçük resimler için projeleri bir kez açıp kaydet.
    for (final info in await services.store.list()) {
      final c = await EditorController.open(services, info.id);
      await _waitFor(() => c.baseImage != null);
      if (info.id == coffee.info.id) {
        c.commitAdjustments('Ayar', c.doc.adjustments.copyWith(contrast: 18, saturation: 14, vignette: -30, filterId: 'film', filterIntensity: 60));
        c.addLayer(
          TextLayer(
            id: newId('l'),
            name: 'Başlık',
            cx: c.doc.canvasWidth / 2,
            cy: c.doc.canvasHeight * 0.16,
            text: 'Kahve Molası',
            fontFamily: 'Anton',
            fontSize: 54,
            letterSpacing: 3,
            shadow: true,
          ),
          'Metin',
        );
        c.addSticker('☕');
        final st = c.doc.layers.last;
        c.updateLayer(st.copyBase(cx: c.doc.canvasWidth * 0.86, cy: c.doc.canvasHeight * 0.8, scale: 0.6, rotation: -0.25), 'Taşı');
        await _waitFor(() => !c.rendering);
      }
      await c.save();
      c.dispose();
    }

    final navigatorKey = GlobalKey<NavigatorState>();
    final boundary = GlobalKey();

    Future<void> shot(String name) async {
      await _frames(25);
      final ro = boundary.currentContext?.findRenderObject();
      if (ro is! RenderRepaintBoundary) {
        log.add('ATLANDI $name: sınır bulunamadı');
        return;
      }
      final image = await ro.toImage(pixelRatio: 1);
      final png = await UiImages.toPng(image);
      image.dispose();
      await File(p.join(outDir, '$name.png')).writeAsBytes(png, flush: true);
      log.add('OK $name (${image.width}x${image.height})');
    }

    Future<EditorController> openEditor(String id) async {
      UnsavedGuard.active = null;
      unawaited(navigatorKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => EditorPage(projectId: id))));
      await _waitFor(() => UnsavedGuard.active?.baseImage != null);
      final c = UnsavedGuard.active!;
      await _waitFor(() => !c.rendering);
      await _frames(20);
      return c;
    }

    // Pencere çözünürlüğünden bağımsız sabit boyutlu çerçeve (CI ekranı küçük olabilir).
    Widget frame(Size size, double topPadding, Widget app) => ColoredBox(
          color: const Color(0xFF05070C),
          child: UnconstrainedBox(
            alignment: Alignment.topLeft,
            child: RepaintBoundary(
              key: boundary,
              child: SizedBox.fromSize(
                size: size,
                child: MediaQuery(
                  data: MediaQueryData(size: size, devicePixelRatio: 1, padding: EdgeInsets.only(top: topPadding)),
                  child: app,
                ),
              ),
            ),
          ),
        );

    // ----------------------------------------------------- Masaüstü (1440x900)
    runApp(frame(const Size(1440, 900), 0, PixelShiftApp(key: const ValueKey('masaustu'), services: services, navigatorKey: navigatorKey)));
    await _frames(40);
    await shot('01_ana_ekran');

    var c = await openEditor(coffee.info.id);
    c.selectLayer(c.doc.layers.first.id);
    c.setTool(EditorTool.select);
    await shot('02_duzenleyici_katmanlar');
    c.setTool(EditorTool.adjust);
    await shot('03_ayarlar');
    c.setTool(EditorTool.filters);
    await _delay(800);
    await shot('04_filtreler');
    c.setTool(EditorTool.ai);
    await shot('05_ai_araclari');
    c.setTool(EditorTool.crop);
    c.setCropAspect(CropAspect.presets[2]);
    await _waitFor(() => !c.rendering);
    await shot('06_kirpma');
    c.cancelCrop();
    navigatorKey.currentState!.pop();
    await _frames(20);

    // ----------------------------------------------------- Telefon (390x844)
    final phoneKey = GlobalKey<NavigatorState>();
    runApp(frame(const Size(390, 844), 24, PixelShiftApp(key: const ValueKey('telefon'), services: services, navigatorKey: phoneKey)));
    await _frames(40);
    await shot('07_telefon_ana_ekran');
    UnsavedGuard.active = null;
    unawaited(phoneKey.currentState!.push(MaterialPageRoute<void>(builder: (_) => EditorPage(projectId: coffee.info.id))));
    await _waitFor(() => UnsavedGuard.active?.baseImage != null);
    c = UnsavedGuard.active!;
    await _frames(30);
    await shot('08_telefon_duzenleyici');
  } catch (e, st) {
    log.add('HATA: $e\n$st');
  } finally {
    await File(p.join(outDir, 'ekran_goruntusu_gunlugu.txt')).writeAsString(log.join('\n'));
    try {
      await temp.delete(recursive: true);
    } catch (_) {}
  }
}

Future<void> _frames(int n) async {
  for (var i = 0; i < n; i++) {
    WidgetsBinding.instance.scheduleFrame();
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 16));
  }
}

Future<void> _delay(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

Future<void> _waitFor(bool Function() condition, {Duration timeout = const Duration(seconds: 60)}) async {
  final end = DateTime.now().add(timeout);
  while (!condition()) {
    if (DateTime.now().isAfter(end)) throw TimeoutException('Koşul zaman aşımına uğradı');
    WidgetsBinding.instance.scheduleFrame();
    await Future<void>.delayed(const Duration(milliseconds: 50));
  }
}
