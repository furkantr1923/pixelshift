import 'dart:io';

import 'package:flutter/foundation.dart';

import '../ai/ai_models.dart';
import '../ai/local_provider.dart';
import '../ai/online_providers.dart';
import '../image_engine/codec.dart';
import '../projects/project_database.dart';

/// Kalıcı uygulama ayarları (SQLite `settings` tablosu).
///
/// API anahtarları kaynak koda gömülmez; kullanıcı girer ve yalnızca bu
/// cihazdaki uygulama veri klasöründe saklanır.
class AppSettings extends ChangeNotifier {
  AppSettings(this._db);

  final ProjectDatabase? _db;

  String _hfToken = '';
  String _removeBgKey = '';
  bool _removeBgFullRes = false;
  final Map<AiTask, String> _hfModels = {};
  final Map<AiTask, String> _taskProvider = {};
  ExportFormat _exportFormat = ExportFormat.jpg;
  int _exportQuality = 92;
  int _previewMaxSide = Platform.isAndroid ? 1600 : 2048;
  bool _firstRunInfoShown = false;

  String get hfToken => _hfToken;
  String get removeBgKey => _removeBgKey;
  bool get removeBgFullRes => _removeBgFullRes;
  Map<AiTask, String> get hfModels => Map.unmodifiable(_hfModels);
  ExportFormat get exportFormat => _exportFormat;
  int get exportQuality => _exportQuality;
  int get previewMaxSide => _previewMaxSide;
  bool get firstRunInfoShown => _firstRunInfoShown;

  Future<void> load() async {
    final db = _db;
    if (db == null) return;
    _hfToken = await db.getSetting('ai.hf.token') ?? '';
    _removeBgKey = await db.getSetting('ai.removebg.key') ?? '';
    _removeBgFullRes = await db.getSetting('ai.removebg.full') == '1';
    for (final t in AiTask.values) {
      final m = await db.getSetting('ai.hf.model.${t.name}');
      if (m != null && m.trim().isNotEmpty) _hfModels[t] = m.trim();
      final p = await db.getSetting('ai.provider.${t.name}');
      if (p != null) _taskProvider[t] = p;
    }
    _exportFormat = ExportFormatInfo.fromName(await db.getSetting('export.format'));
    _exportQuality = int.tryParse(await db.getSetting('export.quality') ?? '') ?? 92;
    _previewMaxSide = int.tryParse(await db.getSetting('preview.maxSide') ?? '') ?? _previewMaxSide;
    _firstRunInfoShown = await db.getSetting('firstRunInfo') == '1';
    notifyListeners();
  }

  Future<void> _set(String key, String? value) async {
    await _db?.setSetting(key, value);
    notifyListeners();
  }

  Future<void> setHfToken(String v) {
    _hfToken = v.trim();
    return _set('ai.hf.token', _hfToken.isEmpty ? null : _hfToken);
  }

  Future<void> setRemoveBgKey(String v) {
    _removeBgKey = v.trim();
    return _set('ai.removebg.key', _removeBgKey.isEmpty ? null : _removeBgKey);
  }

  Future<void> setRemoveBgFullRes(bool v) {
    _removeBgFullRes = v;
    return _set('ai.removebg.full', v ? '1' : null);
  }

  Future<void> setHfModel(AiTask task, String model) {
    final m = model.trim();
    if (m.isEmpty) {
      _hfModels.remove(task);
    } else {
      _hfModels[task] = m;
    }
    return _set('ai.hf.model.${task.name}', m.isEmpty ? null : m);
  }

  String providerIdFor(AiTask task) => _taskProvider[task] ?? 'local';

  Future<void> setProviderFor(AiTask task, String providerId) {
    _taskProvider[task] = providerId;
    return _set('ai.provider.${task.name}', providerId);
  }

  Future<void> setExportDefaults(ExportFormat format, int quality) async {
    _exportFormat = format;
    _exportQuality = quality;
    await _db?.setSetting('export.format', format.name);
    await _set('export.quality', '$quality');
  }

  Future<void> setPreviewMaxSide(int v) {
    _previewMaxSide = v;
    return _set('preview.maxSide', '$v');
  }

  Future<void> markFirstRunInfoShown() {
    _firstRunInfoShown = true;
    return _set('firstRunInfo', '1');
  }

  /// Güncel ayarlarla sağlayıcı listesi (her çağrıda yeni örnekler).
  List<AiProvider> buildProviders() => [
        LocalClassicProvider(),
        HuggingFaceProvider(token: _hfToken, models: _hfModels),
        RemoveBgProvider(apiKey: _removeBgKey, fullResolution: _removeBgFullRes),
      ];
}
