import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path/path.dart' as p;

import '../core/app_info.dart';
import '../core/errors.dart';
import '../core/ids.dart';
import '../editor/document.dart';
import 'project_database.dart';

/// Açılmış bir projenin diskten okunan tüm verisi.
class ProjectData {
  const ProjectData({required this.info, required this.history, required this.labels, required this.index});

  final ProjectInfo info;
  final List<EditDocument> history;
  final List<String> labels;
  final int index;

  EditDocument get current => history[index];
}

/// Projeler uygulamanın kendi klasöründe saklanır:
///
/// ```
/// Projeler/<id>/
///   project.json        belge + düzenleme geçmişi
///   source.jpg          orijinal (asla değiştirilmez)
///   source_<n>.png      AI/klasik işlem sonrası yeni kaynak sürümleri
///   assets/             görsel katmanları
///   thumb.png           ana ekran küçük resmi
/// ```
class ProjectStore {
  ProjectStore({required this.projectsDir, required this.database});

  final String projectsDir;
  final ProjectDatabase database;

  /// Projede saklanan en fazla geçmiş adımı.
  static const int savedHistoryLimit = 40;

  String folderOf(String id) => p.join(projectsDir, id);
  String fileOf(String id, String name) => p.join(folderOf(id), name);
  String assetPath(String id, String asset) => p.join(folderOf(id), 'assets', asset);
  String thumbPath(String id) => p.join(folderOf(id), 'thumb.png');

  Future<ProjectInfo> create({
    required String name,
    required Uint8List sourceBytes,
    required String sourceExtension,
    required int width,
    required int height,
    required EditDocument Function(String sourceFile) documentBuilder,
    String kind = 'photo',
  }) async {
    final id = newId('p');
    final dir = Directory(folderOf(id));
    await dir.create(recursive: true);
    await Directory(p.join(dir.path, 'assets')).create();
    final sourceFile = 'source.$sourceExtension';
    await File(p.join(dir.path, sourceFile)).writeAsBytes(sourceBytes, flush: true);
    final now = DateTime.now();
    final info = ProjectInfo(
      id: id,
      name: name.trim().isEmpty ? 'Adsız proje' : name.trim(),
      createdAt: now,
      updatedAt: now,
      openedAt: now,
      width: width,
      height: height,
      kind: kind,
    );
    final doc = documentBuilder(sourceFile);
    await _writeJson(info, [doc], ['Açılış'], 0);
    await database.upsert(info);
    return info;
  }

  Future<void> save(ProjectInfo info, List<EditDocument> history, List<String> labels, int index, {Uint8List? thumbPng}) async {
    var items = history;
    var lbls = labels;
    var idx = index;
    if (items.length > savedHistoryLimit) {
      final drop = items.length - savedHistoryLimit;
      final dropped = drop > idx ? idx : drop;
      items = items.sublist(dropped);
      lbls = lbls.length == history.length ? lbls.sublist(dropped) : List.filled(items.length, 'Düzenleme');
      idx -= dropped;
      if (items.length > savedHistoryLimit) {
        items = items.sublist(0, savedHistoryLimit);
        lbls = lbls.sublist(0, savedHistoryLimit);
      }
    }
    final updated = info.copyWith(updatedAt: DateTime.now(), width: items[idx].canvasWidth, height: items[idx].canvasHeight);
    await _writeJson(updated, items, lbls, idx);
    if (thumbPng != null) {
      await File(thumbPath(info.id)).writeAsBytes(thumbPng, flush: true);
    }
    await database.upsert(updated);
    // Bellekteki tüm geçmiş (kırpılmamış) başvuruları korunur.
    await _cleanupUnusedFiles(info.id, history);
  }

  Future<void> _writeJson(ProjectInfo info, List<EditDocument> history, List<String> labels, int index) async {
    final json = {
      'format': 'pixelshift-project',
      'formatVersion': AppInfo.projectFormatVersion,
      'app': '${AppInfo.name} ${AppInfo.version}',
      'id': info.id,
      'name': info.name,
      'kind': info.kind,
      'createdAt': info.createdAt.toIso8601String(),
      'updatedAt': info.updatedAt.toIso8601String(),
      'historyIndex': index,
      'historyLabels': labels,
      'history': [for (final d in history) d.toJson()],
    };
    final file = File(fileOf(info.id, 'project.json'));
    final tmp = File('${file.path}.tmp');
    await tmp.writeAsString(const JsonEncoder.withIndent(' ').convert(json), flush: true);
    if (await file.exists()) await file.delete();
    await tmp.rename(file.path);
  }

  Future<ProjectData> load(String id) async {
    final file = File(fileOf(id, 'project.json'));
    if (!await file.exists()) {
      throw const UserFacingException('Proje dosyası bulunamadı. Proje klasörü taşınmış veya silinmiş olabilir.');
    }
    Map<String, Object?> json;
    try {
      json = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
    } catch (_) {
      throw const UserFacingException('Proje dosyası bozuk ve okunamadı.');
    }
    if (json['format'] != 'pixelshift-project') {
      throw const UserFacingException('Bu bir PIXELSHIFT proje dosyası değil.');
    }
    final version = (json['formatVersion'] as num?)?.toInt() ?? 1;
    if (version > AppInfo.projectFormatVersion) {
      throw const UserFacingException('Bu proje daha yeni bir PIXELSHIFT sürümüyle kaydedilmiş. Uygulamayı güncelleyin.');
    }
    final history = <EditDocument>[
      for (final d in (json['history'] as List? ?? const [])) EditDocument.fromJson((d as Map).cast<String, Object?>()),
    ];
    if (history.isEmpty) throw const UserFacingException('Proje geçmişi boş.');
    final labels = [for (final l in (json['historyLabels'] as List? ?? const [])) '$l'];
    final index = ((json['historyIndex'] as num?)?.toInt() ?? history.length - 1).clamp(0, history.length - 1);
    var info = await database.byId(id);
    final now = DateTime.now();
    info ??= ProjectInfo(
      id: id,
      name: json['name'] as String? ?? 'Proje',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ?? now,
      updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ?? now,
      openedAt: now,
      width: history[index].canvasWidth,
      height: history[index].canvasHeight,
      kind: json['kind'] as String? ?? 'photo',
    );
    info = info.copyWith(openedAt: now);
    await database.upsert(info);
    return ProjectData(
      info: info,
      history: history,
      labels: labels.length == history.length ? labels : List.filled(history.length, 'Düzenleme'),
      index: index,
    );
  }

  Future<Uint8List> readFile(String id, String name) async {
    final f = File(fileOf(id, name));
    if (!await f.exists()) throw UserFacingException('Proje dosyası eksik: $name');
    return f.readAsBytes();
  }

  Future<Uint8List> readAsset(String id, String asset) async {
    final f = File(assetPath(id, asset));
    if (!await f.exists()) throw UserFacingException('Katman görseli eksik: $asset');
    return f.readAsBytes();
  }

  /// Katman görseli ekler; dosya adını döndürür.
  Future<String> addAsset(String id, Uint8List bytes, String extension) async {
    final name = '${newId('a')}.$extension';
    await Directory(p.join(folderOf(id), 'assets')).create(recursive: true);
    await File(assetPath(id, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  /// AI/klasik işlem sonucunu yeni kaynak sürümü olarak yazar.
  Future<String> addSourceVersion(String id, Uint8List bytes, String extension) async {
    final name = 'source_${newId('v')}.$extension';
    await File(fileOf(id, name)).writeAsBytes(bytes, flush: true);
    return name;
  }

  Future<ProjectInfo> rename(ProjectInfo info, String name) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw const UserFacingException('Proje adı boş olamaz.');
    final updated = info.copyWith(name: trimmed, updatedAt: DateTime.now());
    await database.upsert(updated);
    final file = File(fileOf(info.id, 'project.json'));
    if (await file.exists()) {
      try {
        final json = (jsonDecode(await file.readAsString()) as Map).cast<String, Object?>();
        json['name'] = trimmed;
        await file.writeAsString(const JsonEncoder.withIndent(' ').convert(json), flush: true);
      } catch (_) {
        // Dosya okunamazsa yalnızca dizin kaydı güncellenir.
      }
    }
    return updated;
  }

  Future<void> delete(String id) async {
    final dir = Directory(folderOf(id));
    if (await dir.exists()) await dir.delete(recursive: true);
    await database.delete(id);
  }

  /// Dizin kaydı olmayan klasörleri (ör. başka cihazdan kopyalanmış) içeri alır.
  Future<List<ProjectInfo>> list() async {
    final known = {for (final i in await database.all()) i.id: i};
    final dir = Directory(projectsDir);
    if (await dir.exists()) {
      await for (final e in dir.list()) {
        if (e is! Directory) continue;
        final id = p.basename(e.path);
        if (known.containsKey(id)) continue;
        if (!await File(p.join(e.path, 'project.json')).exists()) continue;
        try {
          final data = await load(id);
          known[id] = data.info;
        } catch (_) {}
      }
    }
    // Klasörü silinmiş kayıtları temizle.
    for (final id in known.keys.toList()) {
      if (!await File(fileOf(id, 'project.json')).exists()) {
        await database.delete(id);
        known.remove(id);
      }
    }
    final list = known.values.toList()..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  /// Geçmişte artık başvurulmayan kaynak sürümlerini ve katman görsellerini siler.
  Future<void> _cleanupUnusedFiles(String id, List<EditDocument> history) async {
    final usedSources = {for (final d in history) d.sourceFile};
    final usedAssets = <String>{};
    for (final d in history) {
      for (final l in d.layers) {
        final j = l.toJson();
        final a = j['assetFile'];
        if (a is String) usedAssets.add(a);
      }
    }
    try {
      await for (final e in Directory(folderOf(id)).list()) {
        if (e is! File) continue;
        final name = p.basename(e.path);
        // Orijinal kaynak (source.*) her zaman korunur; yalnızca türetilmiş sürümler silinir.
        if (name.startsWith('source_') && !usedSources.contains(name)) await e.delete();
      }
      final assets = Directory(p.join(folderOf(id), 'assets'));
      if (await assets.exists()) {
        await for (final e in assets.list()) {
          if (e is File && !usedAssets.contains(p.basename(e.path))) await e.delete();
        }
      }
    } catch (_) {
      // Temizlik başarısız olursa veri kaybı olmaz; sonraki kayıtta yeniden denenir.
    }
  }
}
