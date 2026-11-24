import 'dart:io';

import 'package:flutter/material.dart';

import 'app/app.dart';
import 'app/services.dart';
import 'core/errors.dart';
import 'screenshot_mode.dart';
import 'self_test.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();

  // CI ve hata ayıklama için: pixelshift.exe --self-test=rapor.txt
  for (final arg in args) {
    if (arg.startsWith('--self-test=')) {
      final code = await runSelfTest(arg.substring('--self-test='.length));
      exit(code);
    }
    if (arg.startsWith('--screenshots=')) {
      registerFontLicenses();
      await runScreenshotMode(arg.substring('--screenshots='.length));
      exit(0);
    }
  }

  registerFontLicenses();
  try {
    final services = await AppServices.create();
    runApp(PixelShiftApp(services: services));
  } catch (error) {
    runApp(StartupErrorApp(message: describeError(error)));
  }
}
