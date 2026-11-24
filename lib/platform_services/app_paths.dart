import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Uygulama verilerinin yalnızca bu cihazda tutulduğu klasörler.
class AppPaths {
  const AppPaths({required this.root, this.portable = false});

  final String root;

  /// Taşınabilir (portable) Windows sürümünde veriler exe'nin yanındadır.
  final bool portable;

  String get projectsDir => p.join(root, 'Projeler');
  String get databasePath => p.join(root, 'pixelshift.db');
  String get tempDir => p.join(root, 'gecici');

  Future<void> ensure() async {
    await Directory(projectsDir).create(recursive: true);
    await Directory(tempDir).create(recursive: true);
  }

  /// Geçici dosyaları temizler (AI ve dışa aktarma ara dosyaları).
  Future<int> clearTemp() async {
    final dir = Directory(tempDir);
    if (!await dir.exists()) return 0;
    var count = 0;
    await for (final e in dir.list()) {
      try {
        await e.delete(recursive: true);
        count++;
      } catch (_) {}
    }
    return count;
  }

  static Future<AppPaths> resolve() async {
    if (Platform.isWindows) {
      final portableDir = _portableDataDir();
      if (portableDir != null) return AppPaths(root: portableDir, portable: true);
    }
    final support = await getApplicationSupportDirectory();
    return AppPaths(root: support.path);
  }

  /// `portable.txt` exe'nin yanında varsa ve klasör yazılabilirse
  /// veriler `PIXELSHIFT-Veri` klasöründe tutulur.
  static String? _portableDataDir() {
    try {
      final exeDir = p.dirname(Platform.resolvedExecutable);
      if (!File(p.join(exeDir, 'portable.txt')).existsSync()) return null;
      final dir = Directory(p.join(exeDir, 'PIXELSHIFT-Veri'));
      dir.createSync(recursive: true);
      final probe = File(p.join(dir.path, '.yazma_testi'));
      probe.writeAsStringSync('ok', flush: true);
      probe.deleteSync();
      return dir.path;
    } catch (_) {
      return null;
    }
  }
}
