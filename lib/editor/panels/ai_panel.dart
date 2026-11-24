import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../ai/ai_models.dart';
import '../../ai/ai_service.dart';
import '../../ai/command_parser.dart';
import '../../ai/online_providers.dart';
import '../../app/services.dart';
import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../core/errors.dart';
import '../../core/format.dart';
import '../../image_engine/classic.dart';
import '../../image_engine/engine.dart';
import '../../image_engine/raster.dart';
import '../../settings/settings_page.dart';
import '../editor_controller.dart';

/// AI ve akıllı düzenleme araçları.
class AiPanel extends StatefulWidget {
  const AiPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  State<AiPanel> createState() => _AiPanelState();
}

class _AiPanelState extends State<AiPanel> {
  final _command = TextEditingController();
  AiTask? _expanded;
  double _tolerance = 32;
  int _factor = 2;
  double _skin = 60;
  String _style = 'oil';
  int _bgTop = 0xFFFFFFFF;
  int _bgBottom = 0xFFFFFFFF;
  Raster? _bgImage;
  String? _bgImageName;

  EditorController get c => widget.controller;

  @override
  void dispose() {
    _command.dispose();
    super.dispose();
  }

  List<AiProvider> _providersFor(AiTask task) =>
      Services.of(context).settings.buildProviders().where((p) => p.supportedTasks.contains(task)).toList();

  AiProvider _selectedProvider(AiTask task) {
    final settings = Services.of(context).settings;
    final list = _providersFor(task);
    final id = settings.providerIdFor(task);
    return list.firstWhere((p) => p.id == id, orElse: () => list.first);
  }

  Map<String, Object?> _params(AiTask task) => switch (task) {
        AiTask.removeBackground => {'tolerance': _tolerance},
        AiTask.replaceBackground => {'topColor': _bgTop, 'bottomColor': _bgBottom, 'backgroundImage': _bgImage},
        AiTask.upscale => {'factor': _factor},
        AiTask.skinSmooth => {'amount': _skin},
        AiTask.style => {'style': _style},
        AiTask.textEdit => {'prompt': _command.text},
        _ => const {},
      };

  Future<void> _run(AiTask task, {AiProvider? provider}) async {
    final p = provider ?? _selectedProvider(task);
    if (!p.isConfigured) {
      showMessage(context, p.configurationHint, error: true);
      return;
    }
    await runAiWithUi(context, c, p, task, _params(task));
  }

  void _applyLocalCommand() {
    final text = _command.text.trim();
    if (text.isEmpty) return;
    final r = c.applyCommand(text);
    if (r.isEmpty) {
      showMessage(
          context,
          'Komut anlaşılamadı. Örnekler: ${CommandParser.examples.take(4).join(', ')}. '
          'Serbest biçimli düzenlemeler için çevrimiçi AI kullanın.',
          error: true);
    } else {
      showMessage(context, r.applied.join(' • '));
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Services.of(context).settings;
    return ListenableBuilder(
      listenable: Listenable.merge([c, settings]),
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 20),
          children: [
            PanelSection(title: 'Komutla düzenle', children: [
              TextField(
                controller: _command,
                minLines: 1,
                maxLines: 3,
                decoration: const InputDecoration(hintText: 'ör. "daha parlak ve biraz sıcak yap"'),
                onSubmitted: (_) => _applyLocalCommand(),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final e in CommandParser.examples.take(5))
                    PxChip(label: e, selected: false, onTap: () => setState(() => _command.text = e)),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(onPressed: _applyLocalCommand, child: const Text('Uygula (yerel)')),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        final hf = _providersFor(AiTask.textEdit).whereType<HuggingFaceProvider>().firstOrNull;
                        if (hf == null) return;
                        if (_command.text.trim().isEmpty) {
                          showMessage(context, 'Önce bir komut yazın.', error: true);
                          return;
                        }
                        _run(AiTask.textEdit, provider: hf);
                      },
                      child: const Text('Çevrimiçi AI'),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              const Text(
                'Yerel yorumlayıcı ışık, renk, filtre ve döndürme komutlarını anlar (AI değildir, çevrimdışı). '
                'Çevrimiçi AI görseli sağlayıcıya gönderir; önce izniniz istenir.',
                style: TextStyle(fontSize: 11.5, color: PxColors.muted, height: 1.35),
              ),
            ]),
            const Divider(height: 24),
            for (final task in AiTask.values)
              if (task != AiTask.textEdit) _taskTile(task),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: OutlinedButton.icon(
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: const Text('AI sağlayıcı ayarları'),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _taskTile(AiTask task) {
    final providers = _providersFor(task);
    final selected = _selectedProvider(task);
    final expanded = _expanded == task;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: expanded ? PxColors.surface3 : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: expanded ? PxColors.primary.withOpacity(0.5) : PxColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              setState(() => _expanded = expanded ? null : task);
              if (!expanded && task == AiTask.objectRemoval) c.setTool(EditorTool.inpaint);
            },
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(_icon(task), size: 20, color: PxColors.accent),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.label, style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(selected.isOnline ? 'Çevrimiçi • ${selected.name}' : 'Çevrimdışı • yerel algoritma',
                            style: TextStyle(fontSize: 11, color: selected.isOnline ? PxColors.warning : PxColors.success)),
                      ],
                    ),
                  ),
                  Icon(expanded ? Icons.expand_less : Icons.expand_more, color: PxColors.muted),
                ],
              ),
            ),
          ),
          if (expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(task.description, style: const TextStyle(fontSize: 12, color: PxColors.muted, height: 1.35)),
                  const SizedBox(height: 10),
                  if (providers.length > 1)
                    DropdownButtonFormField<String>(
                      value: selected.id,
                      isExpanded: true,
                      decoration: const InputDecoration(labelText: 'Sağlayıcı'),
                      items: [
                        for (final p in providers)
                          DropdownMenuItem(
                            value: p.id,
                            child: Text('${p.name}${p.isConfigured ? '' : ' — yapılandırılmadı'}',
                                overflow: TextOverflow.ellipsis),
                          ),
                      ],
                      onChanged: (id) {
                        if (id != null) Services.of(context).settings.setProviderFor(task, id);
                      },
                    ),
                  if (!selected.isConfigured) ...[
                    const SizedBox(height: 8),
                    InfoBox(text: selected.configurationHint, icon: Icons.key_outlined, color: PxColors.warning),
                  ],
                  if (selected.isOnline && selected.modelFor(task) != null) ...[
                    const SizedBox(height: 6),
                    Text('Model: ${selected.modelFor(task)}', style: const TextStyle(fontSize: 11.5, color: PxColors.muted)),
                  ],
                  const SizedBox(height: 8),
                  ..._paramWidgets(task, selected),
                  const SizedBox(height: 10),
                  FilledButton.icon(
                    onPressed: () => _run(task),
                    icon: Icon(selected.isOnline ? Icons.cloud_upload_outlined : Icons.auto_awesome, size: 18),
                    label: Text(task == AiTask.objectRemoval ? 'Boyanan alanı sil' : 'Uygula'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _paramWidgets(AiTask task, AiProvider provider) {
    switch (task) {
      case AiTask.removeBackground:
        if (provider.isOnline) return const [];
        return [
          LabeledSlider(
            label: 'Renk toleransı',
            value: _tolerance,
            min: 5,
            max: 100,
            defaultValue: 32,
            onChanged: (v) => setState(() => _tolerance = v),
          ),
          const InfoBox(text: 'Yerel yöntem kenarlardan başlayarak tek renkli arka planı kaldırır (stüdyo/ürün fotoğrafları). '
              'Karmaşık arka planlar için çevrimiçi sağlayıcı seçin.'),
        ];
      case AiTask.replaceBackground:
        return [
          Row(
            children: [
              ColorButton(color: _bgTop, label: 'Üst renk', onChanged: (v) => setState(() => _bgTop = v)),
              const Spacer(),
              ColorButton(color: _bgBottom, label: 'Alt renk', onChanged: (v) => setState(() => _bgBottom = v)),
            ],
          ),
          const SizedBox(height: 6),
          OutlinedButton.icon(
            icon: const Icon(Icons.image_outlined, size: 18),
            label: Text(_bgImageName == null ? 'Arka plan görseli seç (isteğe bağlı)' : 'Görsel: $_bgImageName'),
            onPressed: _pickBackgroundImage,
          ),
          if (_bgImage != null)
            TextButton(onPressed: () => setState(() => _bgImage = _bgImageName = null), child: const Text('Görseli kaldır')),
          const SizedBox(height: 4),
          const InfoBox(text: 'Önce "Arka plan kaldırma" ile şeffaf alan oluşturun; şeffaf bölgeler seçtiğiniz zeminle doldurulur.'),
        ];
      case AiTask.objectRemoval:
        return [
          LabeledSlider(
            label: 'Fırça boyutu',
            value: c.inpaintBrush,
            min: 4,
            max: 400,
            defaultValue: 40,
            suffix: ' px',
            onChanged: c.setInpaintBrush,
          ),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: () => c.setTool(EditorTool.inpaint),
                  child: Text(c.tool == EditorTool.inpaint ? 'Fırça etkin' : 'Fırçayı etkinleştir'),
                ),
              ),
              const SizedBox(width: 6),
              IconButton(tooltip: 'Son darbeyi geri al', onPressed: c.undoInpaintStroke, icon: const Icon(Icons.undo)),
              IconButton(tooltip: 'Temizle', onPressed: c.clearInpaint, icon: const Icon(Icons.delete_sweep_outlined)),
            ],
          ),
          const InfoBox(text: 'Silmek istediğiniz nesneyi kırmızıyla boyayın. Alan çevresindeki piksellerden doldurulur '
              '(klasik yöntem; küçük/orta nesnelerde ve düzgün zeminlerde en iyi sonucu verir).'),
        ];
      case AiTask.upscale:
        return [
          Row(
            children: [
              PxChip(label: '2×', selected: _factor == 2, onTap: () => setState(() => _factor = 2)),
              const SizedBox(width: 6),
              if (!provider.isOnline) PxChip(label: '4×', selected: _factor == 4, onTap: () => setState(() => _factor = 4)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Sonuç: ${c.doc.canvasWidth * (provider.isOnline ? 2 : _factor)} × ${c.doc.canvasHeight * (provider.isOnline ? 2 : _factor)}',
                  style: const TextStyle(fontSize: 12, color: PxColors.muted),
                ),
              ),
            ],
          ),
          if (provider.isOnline)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: InfoBox(text: 'Çevrimiçi model görseli 1024 px\'e küçültüp 2× büyütür; çok büyük fotoğraflarda yerel büyütme daha uygundur.'),
            ),
        ];
      case AiTask.skinSmooth:
        return [
          LabeledSlider(label: 'Yoğunluk', value: _skin, min: 10, max: 100, defaultValue: 60, suffix: '%', onChanged: (v) => setState(() => _skin = v)),
        ];
      case AiTask.style:
        final styles = provider.isOnline
            ? const {'oil': 'Yağlı boya', 'watercolor': 'Sulu boya', 'sketch': 'Karakalem', 'cartoon': 'Çizgi film', 'anime': 'Anime', 'vangogh': 'Van Gogh'}
            : Classic.styleNames;
        if (!styles.containsKey(_style)) _style = styles.keys.first;
        return [
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final e in styles.entries) PxChip(label: e.value, selected: _style == e.key, onTap: () => setState(() => _style = e.key)),
            ],
          ),
        ];
      default:
        return const [];
    }
  }

  Future<void> _pickBackgroundImage() async {
    final files = Services.of(context).files;
    try {
      final picked = await files.pickFiles();
      if (picked.isEmpty) return;
      final f = picked.first;
      final imported = await ImageEngine.importImage(f.bytes, f.name, 4096);
      setState(() {
        _bgImage = imported.preview;
        _bgImageName = f.name;
      });
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    }
  }

  IconData _icon(AiTask t) => switch (t) {
        AiTask.removeBackground => Icons.person_remove_outlined,
        AiTask.replaceBackground => Icons.wallpaper,
        AiTask.objectRemoval => Icons.healing,
        AiTask.enhance => Icons.auto_fix_high,
        AiTask.upscale => Icons.zoom_out_map,
        AiTask.portrait => Icons.face_retouching_natural,
        AiTask.skinSmooth => Icons.face,
        AiTask.restore => Icons.history_edu,
        AiTask.style => Icons.brush_outlined,
        AiTask.textEdit => Icons.chat_outlined,
      };
}

/// AI görevini izin, ilerleme ve iptal arayüzüyle çalıştırır.
Future<void> runAiWithUi(BuildContext context, EditorController c, AiProvider provider, AiTask task, Map<String, Object?> params) async {
  final stage = ValueNotifier<String>('Hazırlanıyor…');
  final cancel = CancelToken();
  final started = DateTime.now();
  var dialogOpen = false;
  final navigator = Navigator.of(context, rootNavigator: true);

  void openProgress() {
    if (dialogOpen) return;
    dialogOpen = true;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _ProgressDialog(title: task.label, stage: stage, started: started, onCancel: cancel.cancel),
    ).whenComplete(() => dialogOpen = false);
  }

  // İlerleme penceresi hemen açılır; izin penceresi gerekiyorsa onun üzerinde gösterilir.
  final service = AiService(consent: (req) {
    stage.value = 'İzin bekleniyor…';
    return showConsentDialog(context, req);
  });
  openProgress();
  try {
    stage.value = 'Tam çözünürlüklü görüntü hazırlanıyor…';
    final result = await c.runAi(service, provider, task, params: params, progress: (s, _) => stage.value = s, cancel: cancel);
    if (dialogOpen) navigator.pop();
    if (context.mounted && result != null) {
      final took = formatDuration(DateTime.now().difference(started));
      showMessage(context, '${task.label} tamamlandı ($took). ${result.note ?? ''}'.trim());
    }
  } on OperationCancelled {
    if (dialogOpen) navigator.pop();
    if (context.mounted) showMessage(context, provider.isOnline ? 'İşlem iptal edildi. Görsel gönderilmedi veya sonuç kullanılmadı.' : 'İşlem iptal edildi.');
  } catch (e) {
    if (dialogOpen) navigator.pop();
    if (context.mounted) {
      final msg = describeError(e);
      final details = e is UserFacingException ? e.details : null;
      showMessage(context, details == null ? msg : '$msg\n($details)', error: true);
    }
  }
  // Not: [stage] kapanış animasyonu sürerken dinlendiği için burada dispose edilmez.
}

class _ProgressDialog extends StatefulWidget {
  const _ProgressDialog({required this.title, required this.stage, required this.started, required this.onCancel});
  final String title;
  final ValueNotifier<String> stage;
  final DateTime started;
  final VoidCallback onCancel;

  @override
  State<_ProgressDialog> createState() => _ProgressDialogState();
}

class _ProgressDialogState extends State<_ProgressDialog> {
  Timer? _timer;
  bool _cancelling = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = DateTime.now().difference(widget.started);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text(widget.title),
        content: SizedBox(
          width: 340,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const LinearProgressIndicator(),
              const SizedBox(height: 14),
              ValueListenableBuilder<String>(
                valueListenable: widget.stage,
                builder: (_, s, __) => Text(s, style: const TextStyle(fontSize: 13)),
              ),
              const SizedBox(height: 6),
              Text('Geçen süre: ${formatDuration(elapsed)}', style: const TextStyle(fontSize: 12, color: PxColors.muted)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _cancelling
                ? null
                : () {
                    setState(() => _cancelling = true);
                    widget.stage.value = 'İptal ediliyor…';
                    widget.onCancel();
                  },
            child: const Text('İptal'),
          ),
        ],
      ),
    );
  }
}

/// Çevrimiçi gönderim öncesi açık izin penceresi.
Future<bool> showConsentDialog(BuildContext context, ConsentRequest req) async {
  final license = req.model == null ? null : HuggingFaceProvider.knownLicenses[req.model];
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) {
      Widget row(IconData icon, String title, String body, {Color color = PxColors.accent}) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 2),
                      Text(body, style: const TextStyle(fontSize: 12.5, height: 1.4)),
                    ],
                  ),
                ),
              ],
            ),
          );
      return AlertDialog(
        title: const Row(children: [
          Icon(Icons.privacy_tip_outlined, color: PxColors.warning),
          SizedBox(width: 10),
          Expanded(child: Text('Görsel internete gönderilecek')),
        ]),
        content: SizedBox(
          width: 460,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                row(Icons.cloud_outlined, 'Sağlayıcı', '${req.providerName}\n${req.privacy.host}'
                    '${req.model != null ? '\nModel: ${req.model}' : ''}${license != null ? ' (lisans: $license)' : ''}'),
                row(Icons.upload_outlined, 'Ne gönderilecek? (${req.task.label})', req.uploadDescription),
                row(Icons.storage_outlined, 'Veri saklama', req.privacy.dataHandling, color: PxColors.warning),
                row(Icons.payments_outlined, 'Ücret ve sınırlar', req.privacy.limits, color: PxColors.warning),
                Row(
                  children: [
                    const Icon(Icons.link, size: 18, color: PxColors.muted),
                    const SizedBox(width: 10),
                    Expanded(child: SelectableText(req.privacy.policyUrl, style: const TextStyle(fontSize: 12.5, color: PxColors.accent))),
                    IconButton(
                      tooltip: 'Bağlantıyı kopyala',
                      icon: const Icon(Icons.copy, size: 16),
                      onPressed: () => Clipboard.setData(ClipboardData(text: req.privacy.policyUrl)),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text('İzin vermezseniz görsel gönderilmez. Bu izin yalnızca bu işlem için geçerlidir.',
                    style: TextStyle(fontSize: 12, color: PxColors.muted)),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Gönderme')),
          FilledButton.icon(
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.check, size: 18),
            label: const Text('İzin ver ve gönder'),
          ),
        ],
      );
    },
  );
  return result ?? false;
}
