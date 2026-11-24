import 'dart:ui';

import 'package:flutter/material.dart';

import '../editor/editor_controller.dart';

enum UnsavedChoice { save, discard, cancel }

/// Kaydedilmemiş değişiklik koruması: düzenleyici açıkken pencere kapatılır
/// veya geri dönülürse kullanıcıya sorulur.
class UnsavedGuard {
  UnsavedGuard._();

  static EditorController? active;

  static Future<UnsavedChoice> ask(BuildContext context, String projectName) async {
    final r = await showDialog<UnsavedChoice>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Kaydedilmemiş değişiklikler'),
        content: Text('"$projectName" projesinde kaydedilmemiş değişiklikler var. Kaydetmek ister misiniz?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, UnsavedChoice.cancel), child: const Text('İptal')),
          TextButton(onPressed: () => Navigator.pop(context, UnsavedChoice.discard), child: const Text('Kaydetme')),
          FilledButton(onPressed: () => Navigator.pop(context, UnsavedChoice.save), child: const Text('Kaydet')),
        ],
      ),
    );
    return r ?? UnsavedChoice.cancel;
  }

  /// Uygulama kapanış isteği (Windows pencere kapatma).
  static Future<AppExitResponse> handleExit(GlobalKey<NavigatorState> navigatorKey) async {
    final c = active;
    final context = navigatorKey.currentContext;
    if (c == null || !c.isDirty || context == null) return AppExitResponse.exit;
    final choice = await ask(context, c.info.name);
    switch (choice) {
      case UnsavedChoice.save:
        await c.save();
        return c.isDirty ? AppExitResponse.cancel : AppExitResponse.exit;
      case UnsavedChoice.discard:
        return AppExitResponse.exit;
      case UnsavedChoice.cancel:
        return AppExitResponse.cancel;
    }
  }
}
