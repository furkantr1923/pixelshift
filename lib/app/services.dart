import 'package:flutter/widgets.dart';

import '../platform_services/app_paths.dart';
import '../platform_services/file_service.dart';
import '../projects/project_database.dart';
import '../projects/project_store.dart';
import '../settings/app_settings.dart';

/// Uygulama genelinde paylaşılan hizmetler.
class AppServices {
  AppServices({required this.paths, required this.database, required this.store, required this.files, required this.settings});

  final AppPaths paths;
  final ProjectDatabase database;
  final ProjectStore store;
  final FileService files;
  final AppSettings settings;

  static Future<AppServices> create({AppPaths? paths}) async {
    final p = paths ?? await AppPaths.resolve();
    await p.ensure();
    final db = await ProjectDatabase.open(p.databasePath);
    final settings = AppSettings(db);
    await settings.load();
    return AppServices(
      paths: p,
      database: db,
      store: ProjectStore(projectsDir: p.projectsDir, database: db),
      files: FileService(tempDir: p.tempDir),
      settings: settings,
    );
  }
}

class Services extends InheritedWidget {
  const Services({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final w = context.dependOnInheritedWidgetOfExactType<Services>();
    assert(w != null, 'Services bulunamadı');
    return w!.services;
  }

  @override
  bool updateShouldNotify(Services oldWidget) => !identical(services, oldWidget.services);
}
