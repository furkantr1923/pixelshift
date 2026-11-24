import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../app/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/errors.dart';
import '../core/format.dart';
import '../filters/filter_presets.dart';
import '../image_engine/codec.dart';
import 'batch_service.dart';

enum _Status { waiting, working, done, failed }

class _Item {
  _Item(this.file);
  final XFile file;
  _Status status = _Status.waiting;
  String? detail;
}

/// Toplu işlem: çoklu dosyada format dönüştürme, boyutlandırma, filtre.
class BatchPage extends StatefulWidget {
  const BatchPage({super.key});

  @override
  State<BatchPage> createState() => _BatchPageState();
}

class _BatchPageState extends State<BatchPage> {
  final List<_Item> _items = [];
  ExportFormat _format = ExportFormat.jpg;
  int _quality = 90;
  ResizeMode _resize = ResizeMode.none;
  int _maxSide = 2048;
  int _percent = 50;
  String _filter = 'none';
  bool _enhance = false;
  final _suffix = TextEditingController(text: '_pixelshift');
  String? _outputDir;
  bool _running = false;
  bool _cancel = false;
  int _done = 0;
  final Stopwatch _clock = Stopwatch();

  @override
  void dispose() {
    _suffix.dispose();
    super.dispose();
  }

  Future<void> _add({bool gallery = false}) async {
    try {
      final files = await Services.of(context).files.pickXFiles(gallery: gallery);
      setState(() => _items.addAll(files.map(_Item.new)));
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    }
  }

  Future<void> _chooseDir() async {
    final dir = await Services.of(context).files.pickDirectory();
    if (dir != null) setState(() => _outputDir = dir);
  }

  BatchOptions get _options => BatchOptions(
        format: _format,
        quality: _quality,
        resizeMode: _resize,
        maxSide: _maxSide,
        percent: _percent,
        filterId: _filter,
        autoEnhance: _enhance,
        suffix: _suffix.text,
      );

  Future<void> _start() async {
    final services = Services.of(context);
    final android = services.files.isAndroid;
    if (_items.isEmpty) return;
    if (!android && _outputDir == null) {
      await _chooseDir();
      if (_outputDir == null) return;
    }
    setState(() {
      _running = true;
      _cancel = false;
      _done = 0;
      for (final i in _items) {
        i.status = _Status.waiting;
        i.detail = null;
      }
    });
    _clock
      ..reset()
      ..start();
    final options = _options;
    for (final item in _items) {
      if (_cancel) break;
      setState(() => item.status = _Status.working);
      try {
        final bytes = await item.file.readAsBytes();
        final out = await BatchService.process(bytes, item.file.name, options);
        if (android) {
          await services.files.saveToGallery(out.bytes, out.fileName);
        } else {
          final target = _uniquePath(p.join(_outputDir!, out.fileName));
          await File(target).writeAsBytes(out.bytes, flush: true);
        }
        item.status = _Status.done;
        item.detail = '${out.width}×${out.height} • ${formatBytes(out.bytes.length)}';
      } catch (e) {
        item.status = _Status.failed;
        item.detail = describeError(e);
      }
      if (!mounted) return;
      setState(() => _done++);
    }
    _clock.stop();
    if (!mounted) return;
    setState(() => _running = false);
    _showReport();
  }

  String _uniquePath(String path) {
    if (!File(path).existsSync()) return path;
    final dir = p.dirname(path), base = p.basenameWithoutExtension(path), ext = p.extension(path);
    for (var i = 2; i < 10000; i++) {
      final candidate = p.join(dir, '$base ($i)$ext');
      if (!File(candidate).existsSync()) return candidate;
    }
    return path;
  }

  String _reportText() {
    final ok = _items.where((i) => i.status == _Status.done).length;
    final failed = _items.where((i) => i.status == _Status.failed).toList();
    final b = StringBuffer()
      ..writeln('PIXELSHIFT toplu işlem raporu')
      ..writeln('Tarih: ${formatDateTime(DateTime.now())}')
      ..writeln('Süre: ${formatDuration(_clock.elapsed)}')
      ..writeln('Format: ${_format.label}, kalite: $_quality')
      ..writeln('Başarılı: $ok / ${_items.length}')
      ..writeln();
    for (final i in _items) {
      final s = switch (i.status) {
        _Status.done => 'TAMAM',
        _Status.failed => 'HATA',
        _ => 'İŞLENMEDİ',
      };
      b.writeln('[$s] ${i.file.name}${i.detail != null ? ' — ${i.detail}' : ''}');
    }
    if (failed.isNotEmpty) b.writeln('\n${failed.length} dosya işlenemedi.');
    return b.toString();
  }

  void _showReport() {
    final ok = _items.where((i) => i.status == _Status.done).length;
    final failed = _items.where((i) => i.status == _Status.failed).length;
    final android = Services.of(context).files.isAndroid;
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(failed == 0 ? 'Toplu işlem tamamlandı' : 'Toplu işlem tamamlandı (hatalı dosyalar var)'),
        content: Text('Başarılı: $ok\nHatalı: $failed\nİşlenmeyen: ${_items.length - ok - failed}\n'
            'Süre: ${formatDuration(_clock.elapsed)}\n\n'
            '${android ? 'Dosyalar galeride PIXELSHIFT albümüne kaydedildi.' : 'Klasör: $_outputDir'}'),
        actions: [
          if (!android && _outputDir != null) ...[
            TextButton(
              onPressed: () async {
                final path = p.join(_outputDir!, 'pixelshift_rapor_${DateTime.now().millisecondsSinceEpoch}.txt');
                await File(path).writeAsString(_reportText(), flush: true);
                if (context.mounted) showMessage(context, 'Rapor kaydedildi: $path');
              },
              child: const Text('Raporu kaydet'),
            ),
            TextButton(
              onPressed: () => Services.of(context).files.revealInExplorer(_outputDir!),
              child: const Text('Klasörü aç'),
            ),
          ],
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final android = Services.of(context).files.isAndroid;
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final list = Column(
      children: [
        if (_running || _done > 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                LinearProgressIndicator(value: _items.isEmpty ? 0 : _done / _items.length),
                const SizedBox(height: 6),
                Text('$_done / ${_items.length} işlendi • ${formatDuration(_clock.elapsed)}',
                    style: const TextStyle(fontSize: 12, color: PxColors.muted)),
              ],
            ),
          ),
        Expanded(
          child: _items.isEmpty
              ? const Center(
                  child: Text('İşlenecek görselleri ekleyin.', style: TextStyle(color: PxColors.muted)),
                )
              : ListView.builder(
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final it = _items[i];
                    final (icon, color) = switch (it.status) {
                      _Status.waiting => (Icons.schedule, PxColors.muted),
                      _Status.working => (Icons.autorenew, PxColors.accent),
                      _Status.done => (Icons.check_circle, PxColors.success),
                      _Status.failed => (Icons.error, PxColors.danger),
                    };
                    return ListTile(
                      dense: true,
                      leading: Icon(icon, color: color, size: 20),
                      title: Text(it.file.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: it.detail == null ? null : Text(it.detail!, style: TextStyle(color: it.status == _Status.failed ? PxColors.danger : PxColors.muted, fontSize: 12)),
                      trailing: _running
                          ? null
                          : IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => setState(() => _items.removeAt(i))),
                    );
                  },
                ),
        ),
      ],
    );
    final options = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(children: [
          Expanded(
            child: FilledButton.icon(
              onPressed: _running ? null : () => _add(gallery: android),
              icon: const Icon(Icons.add),
              label: Text(android ? 'Galeriden ekle' : 'Görsel ekle'),
            ),
          ),
          if (android) ...[
            const SizedBox(width: 8),
            OutlinedButton(onPressed: _running ? null : () => _add(), child: const Text('Dosyalar')),
          ],
        ]),
        const SizedBox(height: 16),
        const Text('Çıktı formatı', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final f in ExportFormat.values) PxChip(label: f.label, selected: f == _format, onTap: () => setState(() => _format = f)),
        ]),
        if (_format.supportsQuality)
          LabeledSlider(
            label: _format == ExportFormat.webp ? 'Kalite (100 = kayıpsız)' : 'Kalite',
            value: _quality.toDouble(),
            min: 10,
            max: 100,
            defaultValue: 90,
            onChanged: (v) => setState(() => _quality = v.round()),
          ),
        const SizedBox(height: 10),
        const Text('Boyutlandırma', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, children: [
          PxChip(label: 'Değiştirme', selected: _resize == ResizeMode.none, onTap: () => setState(() => _resize = ResizeMode.none)),
          PxChip(label: 'Uzun kenar', selected: _resize == ResizeMode.maxSide, onTap: () => setState(() => _resize = ResizeMode.maxSide)),
          PxChip(label: 'Yüzde', selected: _resize == ResizeMode.percent, onTap: () => setState(() => _resize = ResizeMode.percent)),
        ]),
        if (_resize == ResizeMode.maxSide)
          LabeledSlider(label: 'Uzun kenar en fazla', value: _maxSide.toDouble(), min: 256, max: 8192, defaultValue: 2048, suffix: ' px',
              onChanged: (v) => setState(() => _maxSide = (v / 16).round() * 16)),
        if (_resize == ResizeMode.percent)
          LabeledSlider(label: 'Ölçek', value: _percent.toDouble(), min: 5, max: 200, defaultValue: 50, suffix: '%',
              onChanged: (v) => setState(() => _percent = v.round())),
        const SizedBox(height: 10),
        DropdownButtonFormField<String>(
          value: _filter,
          decoration: const InputDecoration(labelText: 'Filtre (isteğe bağlı)'),
          items: [for (final f in FilterPresets.all) DropdownMenuItem(value: f.id, child: Text(f.name))],
          onChanged: (v) => setState(() => _filter = v ?? 'none'),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Otomatik iyileştir', style: TextStyle(fontSize: 13.5)),
          subtitle: const Text('Pozlama, kontrast ve renk dengesi', style: TextStyle(fontSize: 12)),
          value: _enhance,
          onChanged: (v) => setState(() => _enhance = v),
        ),
        TextField(controller: _suffix, decoration: const InputDecoration(labelText: 'Dosya adı eki')),
        const SizedBox(height: 12),
        if (!android)
          OutlinedButton.icon(
            onPressed: _running ? null : _chooseDir,
            icon: const Icon(Icons.folder_outlined),
            label: Text(_outputDir == null ? 'Çıktı klasörünü seç' : _outputDir!, overflow: TextOverflow.ellipsis),
          )
        else
          const InfoBox(text: 'Çıktılar galeride "PIXELSHIFT" albümüne kaydedilir.'),
        const SizedBox(height: 16),
        _running
            ? OutlinedButton.icon(
                onPressed: () => setState(() => _cancel = true),
                icon: const Icon(Icons.stop),
                label: Text(_cancel ? 'Durduruluyor…' : 'Durdur'),
              )
            : FilledButton.icon(
                onPressed: _items.isEmpty ? null : _start,
                icon: const Icon(Icons.play_arrow),
                label: Text('${_items.length} görseli işle'),
              ),
        const SizedBox(height: 8),
        const Text('Orijinal dosyalar değiştirilmez. Dosyalar sırayla işlenir; bir dosyadaki hata diğerlerini durdurmaz.',
            style: TextStyle(fontSize: 11.5, color: PxColors.muted)),
      ],
    );
    return Scaffold(
      appBar: AppBar(
        title: const Text('Toplu işlem'),
        actions: [
          if (_items.isNotEmpty && !_running)
            TextButton(onPressed: () => setState(_items.clear), child: const Text('Listeyi temizle')),
        ],
      ),
      body: wide
          ? Row(children: [
              Expanded(child: list),
              const VerticalDivider(width: 1),
              SizedBox(width: 380, child: options),
            ])
          : Column(children: [
              Expanded(flex: 5, child: options),
              const Divider(),
              Expanded(flex: 4, child: list),
            ]),
    );
  }
}
