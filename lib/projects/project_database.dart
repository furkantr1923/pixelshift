import 'dart:io';

import 'package:sqflite/sqflite.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart' show databaseFactoryFfi, sqfliteFfiInit;

/// Proje dizini kaydı (SQLite).
class ProjectInfo {
  const ProjectInfo({
    required this.id,
    required this.name,
    required this.createdAt,
    required this.updatedAt,
    required this.openedAt,
    required this.width,
    required this.height,
    this.kind = 'photo',
  });

  final String id;
  final String name;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime openedAt;
  final int width;
  final int height;

  /// photo | design | collage
  final String kind;

  String get kindLabel => switch (kind) {
        'design' => 'Tasarım',
        'collage' => 'Kolaj',
        _ => 'Fotoğraf',
      };

  Map<String, Object?> toRow() => {
        'id': id,
        'name': name,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'opened_at': openedAt.millisecondsSinceEpoch,
        'width': width,
        'height': height,
        'kind': kind,
      };

  factory ProjectInfo.fromRow(Map<String, Object?> r) => ProjectInfo(
        id: r['id']! as String,
        name: r['name']! as String,
        createdAt: DateTime.fromMillisecondsSinceEpoch(r['created_at']! as int),
        updatedAt: DateTime.fromMillisecondsSinceEpoch(r['updated_at']! as int),
        openedAt: DateTime.fromMillisecondsSinceEpoch(r['opened_at']! as int),
        width: r['width']! as int,
        height: r['height']! as int,
        kind: r['kind'] as String? ?? 'photo',
      );

  ProjectInfo copyWith({String? name, DateTime? updatedAt, DateTime? openedAt, int? width, int? height}) => ProjectInfo(
        id: id,
        name: name ?? this.name,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        openedAt: openedAt ?? this.openedAt,
        width: width ?? this.width,
        height: height ?? this.height,
        kind: kind,
      );
}

/// Platforma uygun SQLite fabrikası:
/// Android: null → sqflite eklentisi (sistem SQLite), Windows: FFI + uygulamayla gelen sqlite3.dll.
DatabaseFactory? platformDatabaseFactory() {
  if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
    sqfliteFfiInit();
    return databaseFactoryFfi;
  }
  return null;
}

class ProjectDatabase {
  ProjectDatabase._(this._db);

  final Database _db;

  static Future<ProjectDatabase> open(String path, {DatabaseFactory? factory}) async {
    Future<void> onCreate(Database db, int version) async {
          await db.execute('''
            CREATE TABLE projects (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              created_at INTEGER NOT NULL,
              updated_at INTEGER NOT NULL,
              opened_at INTEGER NOT NULL,
              width INTEGER NOT NULL,
              height INTEGER NOT NULL,
              kind TEXT NOT NULL DEFAULT 'photo'
            )''');
          await db.execute('CREATE INDEX idx_projects_opened ON projects(opened_at DESC)');
          await db.execute('CREATE TABLE settings (key TEXT PRIMARY KEY, value TEXT)');
    }

    final f = factory ?? platformDatabaseFactory();
    final db = f != null
        ? await f.openDatabase(path, options: OpenDatabaseOptions(version: 1, onCreate: onCreate))
        : await openDatabase(path, version: 1, onCreate: onCreate);
    return ProjectDatabase._(db);
  }

  Future<void> upsert(ProjectInfo info) =>
      _db.insert('projects', info.toRow(), conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<ProjectInfo>> all() async {
    final rows = await _db.query('projects', orderBy: 'updated_at DESC');
    return rows.map(ProjectInfo.fromRow).toList();
  }

  Future<List<ProjectInfo>> recent({int limit = 8}) async {
    final rows = await _db.query('projects', orderBy: 'opened_at DESC', limit: limit);
    return rows.map(ProjectInfo.fromRow).toList();
  }

  Future<ProjectInfo?> byId(String id) async {
    final rows = await _db.query('projects', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : ProjectInfo.fromRow(rows.first);
  }

  Future<void> delete(String id) => _db.delete('projects', where: 'id = ?', whereArgs: [id]);

  Future<String?> getSetting(String key) async {
    final rows = await _db.query('settings', where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> setSetting(String key, String? value) async {
    if (value == null) {
      await _db.delete('settings', where: 'key = ?', whereArgs: [key]);
    } else {
      await _db.insert('settings', {'key': key, 'value': value}, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  Future<void> close() => _db.close();
}
