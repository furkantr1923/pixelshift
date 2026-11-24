import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/errors.dart';
import '../core/format.dart';
import '../editor/editor_controller.dart';
import '../image_engine/codec.dart';
import 'export_service.dart';

/// Dışa aktarma penceresi: format, kalite ve çözünürlük.
Future<void> showExportDialog(BuildContext context, EditorController controller) {
  return showDialog<void>(context: context, builder: (_) => _ExportDialog(controller: controller));
}

class _ExportDialog extends StatefulWidget {
  const _ExportDialog({required this.controller});
  final EditorController controller;

  @override
  State<_ExportDialog> createState() => _ExportDialogState();
}

class _ExportDialogState extends State<_ExportDialog> {
  late ExportFormat _format;
  late int _quality;
  double _percent = 100;
  bool _busy = false;
  String _stage = '';
  double? _fraction;
  late final bool _hasAlpha = widget.controller.sourcePreview?.hasTransparency ?? false;

  @override
  void initState() {
    super.initState();
    final s = Services.of(context).settings;
    _format = s.exportFormat;
    _quality = s.exportQuality;
  }

  int get _w => math.max(1, (widget.controller.doc.canvasWidth * _percent / 100).round());
  int get _h => math.max(1, (widget.controller.doc.canvasHeight * _percent / 100).round());

  String get _fileName {
    final base = safeFileName(widget.controller.info.name);
    return '${base}_pixelshift.${_format.extension}';
  }

  Future<void> _export({required bool share}) async {
    final services = Services.of(context);
    setState(() {
      _busy = true;
      _stage = 'Hazırlanıyor…';
    });
    try {
      await services.settings.setExportDefaults(_format, _quality);
      final out = await ExportService.export(
        store: services.store,
        projectId: widget.controller.info.id,
        doc: widget.controller.doc,
        options: ExportOptions(format: _format, quality: _quality, width: _w, height: _h),
        progress: (s, f) {
          if (mounted) {
            setState(() {
              _stage = s;
              _fraction = f;
            });
          }
        },
      );
      if (!mounted) return;
      setState(() => _stage = share ? 'Paylaşım hazırlanıyor…' : 'Kaydediliyor…');
      if (share) {
        await services.files.share(out.bytes, _fileName, _format.mimeType);
        if (mounted) Navigator.pop(context);
        return;
      }
      final saved = await services.files.saveImage(out.bytes, _fileName, _format);
      if (!mounted) return;
      if (saved == null) {
        setState(() => _busy = false);
        return;
      }
      Navigator.pop(context);
      showMessage(context,
          'Kaydedildi: ${saved.description} • ${out.width}×${out.height} • ${formatBytes(out.bytes.length)} • ${formatDuration(out.elapsed)}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      showMessage(context, 'Dışa aktarma başarısız: ${describeError(e)}', error: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mp = _w * _h / 1e6;
    return AlertDialog(
      title: const Text('Dışa aktar'),
      content: SizedBox(
        width: 420,
        child: _busy
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  LinearProgressIndicator(value: _fraction),
                  const SizedBox(height: 12),
                  Text(_stage),
                  const SizedBox(height: 4),
                  Text('$_w × $_h px', style: const TextStyle(color: PxColors.muted, fontSize: 12)),
                ],
              )
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text('Format', style: TextStyle(fontSize: 12, color: PxColors.muted)),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final f in ExportFormat.values)
                          PxChip(label: f.label, selected: f == _format, onTap: () => setState(() => _format = f)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    if (_format.supportsQuality)
                      LabeledSlider(
                        label: _format == ExportFormat.webp ? 'Kalite (100 = kayıpsız)' : 'Kalite',
                        value: _quality.toDouble(),
                        min: 10,
                        max: 100,
                        defaultValue: 92,
                        onChanged: (v) => setState(() => _quality = v.round()),
                      ),
                    LabeledSlider(
                      label: 'Çözünürlük',
                      value: _percent,
                      min: 10,
                      max: 100,
                      defaultValue: 100,
                      suffix: '%',
                      onChanged: (v) => setState(() => _percent = v.roundToDouble()),
                    ),
                    Wrap(
                      spacing: 6,
                      children: [
                        for (final p in [100.0, 75.0, 50.0, 25.0])
                          PxChip(label: '%${p.round()}', selected: _percent == p, onTap: () => setState(() => _percent = p)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text('Çıktı: $_w × $_h piksel (${mp.toStringAsFixed(1).replaceAll('.', ',')} MP)',
                        style: const TextStyle(fontSize: 13)),
                    const SizedBox(height: 10),
                    if (!_format.supportsTransparency && _hasAlpha)
                      const InfoBox(text: 'Bu format şeffaflığı desteklemez; şeffaf alanlar beyazla doldurulur. Şeffaflık için PNG, WEBP veya TIFF seçin.'),
                    const SizedBox(height: 6),
                    const InfoBox(
                      icon: Icons.shield_outlined,
                      color: PxColors.success,
                      text: 'Gizlilik: dışa aktarılan dosyada EXIF/konum bilgisi bulunmaz. İşlem tamamen cihazınızda yapılır.',
                    ),
                    if (mp > 60) ...[
                      const SizedBox(height: 6),
                      const InfoBox(
                          icon: Icons.memory, color: PxColors.warning, text: 'Çok büyük çıktı: işlem uzun sürebilir ve yüksek bellek kullanır.'),
                    ],
                  ],
                ),
              ),
      ),
      actions: _busy
          ? const []
          : [
              TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
              if (Platform.isAndroid)
                OutlinedButton.icon(
                  onPressed: () => _export(share: true),
                  icon: const Icon(Icons.share_outlined, size: 18),
                  label: const Text('Paylaş'),
                ),
              FilledButton.icon(
                onPressed: () => _export(share: false),
                icon: const Icon(Icons.download_outlined, size: 18),
                label: Text(Platform.isAndroid ? 'Galeriye kaydet' : 'Kaydet…'),
              ),
            ],
    );
  }
}
