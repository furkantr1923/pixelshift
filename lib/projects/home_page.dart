import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../batch_processing/batch_page.dart';
import '../collage/collage_page.dart';
import '../core/errors.dart';
import '../core/format.dart';
import '../editor/editor_page.dart';
import '../image_engine/engine.dart';
import '../platform_services/file_service.dart';
import '../settings/about_page.dart';
import '../settings/settings_page.dart';
import '../templates/templates.dart';
import '../templates/templates_page.dart';
import 'project_database.dart';
import 'project_factory.dart';

/// Ana ekran: yeni proje başlatma ve kayıtlı projeler.
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<ProjectInfo>? _projects;
  bool _busy = false;
  String _busyText = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_projects == null) _reload();
  }

  Future<void> _reload() async {
    try {
      final list = await Services.of(context).store.list();
      if (mounted) setState(() => _projects = list);
    } catch (e) {
      if (mounted) {
        setState(() => _projects = const []);
        showMessage(context, 'Projeler okunamadı: ${describeError(e)}', error: true);
      }
    }
  }

  Future<void> _run(String text, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _busyText = text;
    });
    try {
      await action();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _openEditor(ProjectInfo info, {String? note}) async {
    if (note != null && mounted) showMessage(context, note);
    await Navigator.of(context).push(MaterialPageRoute(builder: (_) => EditorPage(projectId: info.id)));
    if (mounted) _reload();
  }

  Future<void> _openPhoto({bool gallery = false}) async {
    final services = Services.of(context);
    final List<PickedFile> picked;
    try {
      picked = gallery ? await services.files.pickFromGallery() : await services.files.pickFiles();
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
      return;
    }
    if (picked.isEmpty || !mounted) return;
    final f = picked.first;
    final factory = ProjectFactory(services);
    CreatedProject? created;
    await _run('"${f.name}" açılıyor…', () async {
      final imported = await factory.importPicked(f);
      final mp = imported.width * imported.height / 1e6;
      if (mp > ImageEngine.largeImageMegapixels && mounted) {
        final ok = await confirm(context,
            title: 'Büyük görsel',
            message: 'Bu görsel ${imported.width}×${imported.height} (${mp.toStringAsFixed(0)} MP). '
                'Önizleme küçültülmüş çalışır, ancak dışa aktarma ve AI işlemleri uzun sürebilir ve çok bellek kullanabilir. Devam edilsin mi?',
            ok: 'Devam et');
        if (!ok) return;
      }
      created = await factory.fromFile(f, imported: imported);
    });
    final c = created;
    if (c != null && mounted) await _openEditor(c.info, note: c.note);
  }

  /// Uygulamayla gelen örnek fotoğrafla (CC0) hızlı deneme projesi.
  Future<void> _sample() async {
    final services = Services.of(context);
    CreatedProject? created;
    await _run('Örnek proje hazırlanıyor…', () async {
      final data = await rootBundle.load('assets/demo/kahve.jpg');
      final bytes = data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      created = await ProjectFactory(services).fromFile(PickedFile('Örnek — Kahve molası.jpg', bytes));
    });
    if (created != null && mounted) await _openEditor(created!.info);
  }

  Future<void> _newBlank() async {
    final result = await showDialog<(String, int, int, int)>(context: context, builder: (_) => const _BlankCanvasDialog());
    if (result == null || !mounted) return;
    final services = Services.of(context);
    CreatedProject? created;
    await _run('Tuval oluşturuluyor…', () async {
      created = await ProjectFactory(services).blank(result.$1, result.$2, result.$3, result.$4, result.$4);
    });
    if (created != null && mounted) await _openEditor(created!.info);
  }

  Future<void> _templates() async {
    final t = await Navigator.of(context).push<DesignTemplate>(MaterialPageRoute(builder: (_) => const TemplatesPage()));
    if (t == null || !mounted) return;
    final services = Services.of(context);
    CreatedProject? created;
    await _run('Şablon hazırlanıyor…', () async => created = await ProjectFactory(services).fromTemplate(t));
    if (created != null && mounted) await _openEditor(created!.info);
  }

  Future<void> _collage() async {
    final created = await Navigator.of(context).push<CreatedProject>(MaterialPageRoute(builder: (_) => const CollagePage()));
    if (created != null && mounted) await _openEditor(created.info, note: created.note);
  }

  Future<void> _projectMenu(ProjectInfo p, String action) async {
    final store = Services.of(context).store;
    switch (action) {
      case 'open':
        await _openEditor(p);
      case 'rename':
        final name = await promptText(context, title: 'Projeyi yeniden adlandır', initial: p.name, label: 'Proje adı');
        if (name == null) return;
        await _run('Kaydediliyor…', () async => store.rename(p, name));
        _reload();
      case 'delete':
        final ok = await confirm(context,
            title: 'Projeyi sil', message: '"${p.name}" ve tüm düzenleme geçmişi kalıcı olarak silinecek. Orijinal fotoğraf dosyanız etkilenmez.', ok: 'Sil', danger: true);
        if (!ok) return;
        await _run('Siliniyor…', () async => store.delete(p.id));
        _reload();
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final services = Services.of(context);
    final actions = <_Action>[
      _Action(Icons.folder_open_outlined, Platform.isAndroid ? 'Dosyalardan aç' : 'Fotoğraf aç', 'JPG, PNG, WEBP, TIFF, PSD, RAW…', () => _openPhoto()),
      if (Platform.isAndroid) _Action(Icons.photo_library_outlined, 'Galeriden seç', 'Telefon galerisi', () => _openPhoto(gallery: true)),
      _Action(Icons.dashboard_customize_outlined, 'Şablonlar', 'Poster, kapak, hikâye', _templates),
      _Action(Icons.grid_view, 'Kolaj', 'Hazır düzenler', _collage),
      _Action(Icons.crop_square, 'Boş tuval', 'Özel boyut', _newBlank),
      _Action(Icons.burst_mode_outlined, 'Toplu işlem', 'Dönüştür, boyutlandır', () {
        Navigator.of(context).push(MaterialPageRoute(builder: (_) => const BatchPage()));
      }),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(borderRadius: BorderRadius.circular(7), child: Image.asset('assets/icon/app_icon.png', width: 28, height: 28)),
            const SizedBox(width: 10),
            ShaderMask(
              shaderCallback: (r) => PxColors.brandGradient.createShader(r),
              child: const Text('PIXELSHIFT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 2, color: Colors.white)),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Ayarlar',
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
          ),
          IconButton(
            tooltip: 'Hakkında',
            icon: const Icon(Icons.info_outline),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: Stack(
        children: [
          RefreshIndicator(
            onRefresh: _reload,
            child: CustomScrollView(
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 20, wide ? 32 : 16, 8),
                  sliver: SliverToBoxAdapter(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(wide ? 'Ne düzenlemek istersiniz?' : 'Yeni başla',
                            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 4),
                        const Text('Fotoğraflarınız cihazınızda kalır. Temel düzenleme internetsiz çalışır.',
                            style: TextStyle(color: PxColors.muted, fontSize: 13)),
                        const SizedBox(height: 16),
                        LayoutBuilder(builder: (context, constraints) {
                          final cols = constraints.maxWidth >= 1100 ? 6 : (constraints.maxWidth >= 700 ? 3 : 2);
                          final w = (constraints.maxWidth - (cols - 1) * 12) / cols;
                          return Wrap(
                            spacing: 12,
                            runSpacing: 12,
                            children: [for (final a in actions) SizedBox(width: w, child: _ActionCard(action: a))],
                          );
                        }),
                      ],
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 18, wide ? 32 : 16, 10),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        const Text('Projeler', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                        const SizedBox(width: 8),
                        if (_projects != null)
                          Text('${_projects!.length}', style: const TextStyle(color: PxColors.muted)),
                        const Spacer(),
                        if (services.paths.portable)
                          const Chip(label: Text('Taşınabilir mod', style: TextStyle(fontSize: 11))),
                      ],
                    ),
                  ),
                ),
                if (_projects == null)
                  const SliverFillRemaining(child: Center(child: CircularProgressIndicator()))
                else if (_projects!.isEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.all(40),
                      child: Column(
                        children: [
                          const Icon(Icons.photo_size_select_actual_outlined, size: 54, color: PxColors.border),
                          const SizedBox(height: 10),
                          const Text('Henüz proje yok. Bir fotoğraf açarak başlayın.', style: TextStyle(color: PxColors.muted)),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _sample,
                            icon: const Icon(Icons.local_cafe_outlined, size: 18),
                            label: const Text('Örnek fotoğrafla dene'),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(wide ? 32 : 16, 0, wide ? 32 : 16, 32),
                    sliver: SliverGrid(
                      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                        maxCrossAxisExtent: wide ? 240 : 200,
                        mainAxisSpacing: 14,
                        crossAxisSpacing: 14,
                        childAspectRatio: 0.82,
                      ),
                      delegate: SliverChildBuilderDelegate(
                        (context, i) {
                          final p = _projects![i];
                          return _ProjectCard(
                            project: p,
                            thumbPath: services.store.thumbPath(p.id),
                            onOpen: () => _projectMenu(p, 'open'),
                            onMenu: (a) => _projectMenu(p, a),
                          );
                        },
                        childCount: _projects!.length,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_busy) BusyOverlay(message: _busyText),
        ],
      ),
    );
  }
}

class _Action {
  const _Action(this.icon, this.title, this.subtitle, this.onTap);
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action});
  final _Action action;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: PxColors.surface2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: PxColors.border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: action.onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(gradient: PxColors.brandGradient, borderRadius: BorderRadius.circular(10)),
                child: Icon(action.icon, color: Colors.white, size: 22),
              ),
              const SizedBox(height: 12),
              Text(action.title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              const SizedBox(height: 2),
              Text(action.subtitle, style: const TextStyle(color: PxColors.muted, fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({required this.project, required this.thumbPath, required this.onOpen, required this.onMenu});
  final ProjectInfo project;
  final String thumbPath;
  final VoidCallback onOpen;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final thumb = File(thumbPath);
    return Material(
      color: PxColors.surface2,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: PxColors.border)),
      child: InkWell(
        onTap: onOpen,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Container(
                color: PxColors.canvas,
                child: thumb.existsSync()
                    // Bellekten okunur: dosya yolu önbelleği güncel küçük resmi gizlemesin.
                    ? Image.memory(thumb.readAsBytesSync(), fit: BoxFit.contain, gaplessPlayback: true)
                    : const Icon(Icons.image_outlined, size: 40, color: PxColors.border),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 4, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(project.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                        const SizedBox(height: 2),
                        Text('${project.kindLabel} • ${formatRelative(project.updatedAt)}',
                            maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: PxColors.muted, fontSize: 11.5)),
                      ],
                    ),
                  ),
                  PopupMenuButton<String>(
                    tooltip: 'Proje işlemleri',
                    icon: const Icon(Icons.more_vert, size: 18),
                    onSelected: onMenu,
                    itemBuilder: (_) => const [
                      PopupMenuItem(value: 'open', child: Text('Aç')),
                      PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
                      PopupMenuItem(value: 'delete', child: Text('Sil', style: TextStyle(color: PxColors.danger))),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Boş tuval: ad, boyut ve zemin rengi.
class _BlankCanvasDialog extends StatefulWidget {
  const _BlankCanvasDialog();

  @override
  State<_BlankCanvasDialog> createState() => _BlankCanvasDialogState();
}

class _BlankCanvasDialogState extends State<_BlankCanvasDialog> {
  final _name = TextEditingController(text: 'Yeni tasarım');
  final _w = TextEditingController(text: '1080');
  final _h = TextEditingController(text: '1080');
  int _color = 0xFFFFFFFF;

  @override
  void dispose() {
    _name.dispose();
    _w.dispose();
    _h.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Boş tuval'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(controller: _name, decoration: const InputDecoration(labelText: 'Proje adı')),
              const SizedBox(height: 12),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final p in CanvasPreset.all)
                    PxChip(
                      label: '${p.name} (${p.width}×${p.height})',
                      selected: _w.text == '${p.width}' && _h.text == '${p.height}',
                      onTap: () => setState(() {
                        _w.text = '${p.width}';
                        _h.text = '${p.height}';
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(child: TextField(controller: _w, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Genişlik (px)'), onChanged: (_) => setState(() {}))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: _h, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Yükseklik (px)'), onChanged: (_) => setState(() {}))),
                ],
              ),
              const SizedBox(height: 12),
              ColorButton(color: _color, label: 'Zemin rengi', allowTransparent: true, onChanged: (v) => setState(() => _color = v)),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(
          onPressed: () {
            final w = int.tryParse(_w.text.trim()), h = int.tryParse(_h.text.trim());
            if (w == null || h == null || w < 16 || h < 16 || w > 12000 || h > 12000) {
              showMessage(context, 'Boyut 16 ile 12000 piksel arasında olmalı.', error: true);
              return;
            }
            Navigator.pop(context, (_name.text.trim().isEmpty ? 'Yeni tasarım' : _name.text.trim(), w, h, _color));
          },
          child: const Text('Oluştur'),
        ),
      ],
    );
  }
}
