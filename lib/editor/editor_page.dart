import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/unsaved_guard.dart';
import '../app/widgets.dart';
import '../core/errors.dart';
import '../core/format.dart';
import '../export/export_dialog.dart';
import '../settings/about_page.dart';
import 'canvas_view.dart';
import 'editor_controller.dart';
import 'panels/adjust_panel.dart';
import 'panels/ai_panel.dart';
import 'panels/crop_panel.dart';
import 'panels/filter_panel.dart';
import 'panels/insert_panels.dart';
import 'panels/layer_panels.dart';

/// Düzenleyici ekranı. Geniş ekranda (Windows) masaüstü düzeni,
/// dar ekranda (Android telefon) dokunmatik düzen kullanılır.
class EditorPage extends StatefulWidget {
  const EditorPage({super.key, required this.projectId});
  final String projectId;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  EditorController? _c;
  final ViewportController _viewport = ViewportController();
  final FocusNode _rootFocus = FocusNode(debugLabel: 'editor');
  String? _error;
  bool _mobilePanelOpen = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null && _error == null) _open();
  }

  Future<void> _open() async {
    final services = Services.of(context);
    try {
      final c = await EditorController.open(services, widget.projectId);
      if (!mounted) {
        c.dispose();
        return;
      }
      c.onMessage = (m, {bool error = false}) {
        if (mounted) showMessage(context, m, error: error);
      };
      UnsavedGuard.active = c;
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => _error = describeError(e));
    }
  }

  @override
  void dispose() {
    if (identical(UnsavedGuard.active, _c)) UnsavedGuard.active = null;
    _c?.dispose();
    _viewport.dispose();
    _rootFocus.dispose();
    super.dispose();
  }

  Future<void> _handlePop() async {
    final c = _c;
    if (c == null || !c.isDirty) {
      if (mounted) Navigator.of(context).pop();
      return;
    }
    final choice = await UnsavedGuard.ask(context, c.info.name);
    if (choice == UnsavedChoice.cancel) return;
    if (choice == UnsavedChoice.save) {
      await c.save();
      if (c.isDirty) return;
    }
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _addImageLayer() async {
    final c = _c!;
    final files = Services.of(context).files;
    try {
      final picked = files.isAndroid ? await files.pickFromGallery() : await files.pickFiles();
      if (picked.isEmpty) return;
      await c.addImageLayer(picked.first.bytes, picked.first.name);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    }
  }

  Future<void> _rename() async {
    final c = _c!;
    final name = await promptText(context, title: 'Projeyi yeniden adlandır', initial: c.info.name, label: 'Proje adı');
    if (name == null) return;
    try {
      await c.rename(name);
    } catch (e) {
      if (mounted) showMessage(context, describeError(e), error: true);
    }
  }

  void _deleteSelected() {
    final c = _c!;
    final id = c.selectedLayerId;
    if (id != null) c.deleteLayer(id);
  }

  Map<ShortcutActivator, VoidCallback> _shortcuts(EditorController c) => {
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true): c.undo,
        const SingleActivator(LogicalKeyboardKey.keyY, control: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true): c.redo,
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () => unawaited(c.save()),
        const SingleActivator(LogicalKeyboardKey.keyE, control: true): () => showExportDialog(context, c),
        const SingleActivator(LogicalKeyboardKey.keyD, control: true): () {
          final id = c.selectedLayerId;
          if (id != null) c.duplicateLayer(id);
        },
        const SingleActivator(LogicalKeyboardKey.delete): _deleteSelected,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true): _viewport.fit,
        const SingleActivator(LogicalKeyboardKey.digit1, control: true): _viewport.actualPixels,
        const SingleActivator(LogicalKeyboardKey.equal, control: true): () => _viewport.zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.add, control: true): () => _viewport.zoomBy(1.25),
        const SingleActivator(LogicalKeyboardKey.minus, control: true): () => _viewport.zoomBy(0.8),
        const SingleActivator(LogicalKeyboardKey.escape): () {
          if (c.tool == EditorTool.crop) {
            c.cancelCrop();
          } else {
            c.selectLayer(null);
            c.setTool(EditorTool.select);
          }
        },
        const SingleActivator(LogicalKeyboardKey.enter): () {
          if (c.tool == EditorTool.crop) c.applyCrop();
        },
        const SingleActivator(LogicalKeyboardKey.keyV): () => c.setTool(EditorTool.select),
        const SingleActivator(LogicalKeyboardKey.keyC): () => c.setTool(EditorTool.crop),
        const SingleActivator(LogicalKeyboardKey.keyT): () => c.setTool(EditorTool.text),
      };

  /// Kısayollar yalnızca bir metin alanına yazılmıyorken çalışır; böylece
  /// metin kutusunda Ctrl+Z, Delete veya harf tuşları düzenleyiciyi etkilemez.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final c = _c;
    if (c == null || (event is! KeyDownEvent && event is! KeyRepeatEvent)) return KeyEventResult.ignored;
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        (focusContext.widget is EditableText || focusContext.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return KeyEventResult.ignored;
    }
    for (final e in _shortcuts(c).entries) {
      if (e.key.accepts(event, HardwareKeyboard.instance)) {
        e.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (_error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Proje açılamadı')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48, color: PxColors.danger),
                const SizedBox(height: 12),
                Text(_error!, textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Geri dön')),
              ],
            ),
          ),
        ),
      );
    }
    if (c == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [CircularProgressIndicator(), SizedBox(height: 14), Text('Proje açılıyor…')],
          ),
        ),
      );
    }
    final wide = MediaQuery.sizeOf(context).width >= 900;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) => PopScope(
        canPop: !c.isDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handlePop();
        },
        child: Focus(
          focusNode: _rootFocus,
          autofocus: true,
          onKeyEvent: _onKey,
          child: Stack(
            children: [
              wide ? _desktop(c) : _mobile(c),
              if (c.busyMessage != null) BusyOverlay(message: c.busyMessage!),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================ Masaüstü

  Widget _desktop(EditorController c) {
    return Scaffold(
      body: Column(
        children: [
          _menuBar(c),
          const Divider(),
          Expanded(
            child: Row(
              children: [
                _toolRail(c),
                const VerticalDivider(width: 1),
                Expanded(child: _canvasArea(c)),
                const VerticalDivider(width: 1),
                SizedBox(width: 330, child: _rightPanel(c)),
              ],
            ),
          ),
          const Divider(),
          _statusBar(c),
        ],
      ),
    );
  }

  Widget _menuBar(EditorController c) {
    MenuItemButton item(String label, VoidCallback? onTap, {IconData? icon, MenuSerializableShortcut? shortcut}) =>
        MenuItemButton(
          onPressed: onTap,
          shortcut: shortcut,
          leadingIcon: icon == null ? null : Icon(icon, size: 18),
          child: Text(label),
        );
    return Container(
      color: PxColors.surface,
      height: 44,
      child: Row(
        children: [
          const SizedBox(width: 8),
          ShaderMask(
            shaderCallback: (r) => PxColors.brandGradient.createShader(r),
            child: const Text('PIXELSHIFT', style: TextStyle(fontWeight: FontWeight.w800, letterSpacing: 1.5, color: Colors.white)),
          ),
          const SizedBox(width: 12),
          // MenuBar yatay kaydırılabilir; sınırlı genişlik gerektirir.
          Expanded(
            flex: 3,
            child: MenuBar(
            style: const MenuStyle(
              backgroundColor: WidgetStatePropertyAll(PxColors.surface),
              elevation: WidgetStatePropertyAll(0),
            ),
            children: [
              SubmenuButton(menuChildren: [
                item('Kaydet', () => c.save(), icon: Icons.save_outlined, shortcut: const SingleActivator(LogicalKeyboardKey.keyS, control: true)),
                item('Dışa aktar…', () => showExportDialog(context, c),
                    icon: Icons.ios_share, shortcut: const SingleActivator(LogicalKeyboardKey.keyE, control: true)),
                item('Projeyi yeniden adlandır…', _rename, icon: Icons.drive_file_rename_outline),
                const Divider(),
                item('Projelere dön', _handlePop, icon: Icons.arrow_back),
              ], child: const Text('Dosya')),
              SubmenuButton(menuChildren: [
                item('Geri al${c.history.undoLabel != null ? ': ${c.history.undoLabel}' : ''}', c.canUndo ? c.undo : null,
                    icon: Icons.undo, shortcut: const SingleActivator(LogicalKeyboardKey.keyZ, control: true)),
                item('Yinele${c.history.redoLabel != null ? ': ${c.history.redoLabel}' : ''}', c.canRedo ? c.redo : null,
                    icon: Icons.redo, shortcut: const SingleActivator(LogicalKeyboardKey.keyY, control: true)),
                const Divider(),
                item('Katmanı çoğalt', c.selectedLayerId == null ? null : () => c.duplicateLayer(c.selectedLayerId!),
                    icon: Icons.copy, shortcut: const SingleActivator(LogicalKeyboardKey.keyD, control: true)),
                item('Katmanı sil', c.selectedLayerId == null ? null : _deleteSelected,
                    icon: Icons.delete_outline, shortcut: const SingleActivator(LogicalKeyboardKey.delete)),
                item('Ayarları sıfırla', c.doc.adjustments.isNeutral ? null : c.resetAdjustments, icon: Icons.restart_alt),
              ], child: const Text('Düzen')),
              SubmenuButton(menuChildren: [
                item('Yakınlaştır', () => _viewport.zoomBy(1.25),
                    icon: Icons.zoom_in, shortcut: const SingleActivator(LogicalKeyboardKey.equal, control: true)),
                item('Uzaklaştır', () => _viewport.zoomBy(0.8),
                    icon: Icons.zoom_out, shortcut: const SingleActivator(LogicalKeyboardKey.minus, control: true)),
                item('Ekrana sığdır', _viewport.fit,
                    icon: Icons.fit_screen, shortcut: const SingleActivator(LogicalKeyboardKey.digit0, control: true)),
                item('Gerçek boyut (%100)', _viewport.actualPixels,
                    icon: Icons.crop_free, shortcut: const SingleActivator(LogicalKeyboardKey.digit1, control: true)),
              ], child: const Text('Görünüm')),
              SubmenuButton(menuChildren: [
                item('Metin ekle', () => c.addText(), icon: Icons.text_fields),
                item('Şekil ekle', () => c.setTool(EditorTool.shapes), icon: Icons.category_outlined),
                item('Çıkartma ekle', () => c.setTool(EditorTool.stickers), icon: Icons.emoji_emotions_outlined),
                item('Görsel katman ekle…', _addImageLayer, icon: Icons.add_photo_alternate_outlined),
                const Divider(),
                item('Maske', () => c.setTool(EditorTool.mask), icon: Icons.brush),
              ], child: const Text('Katman')),
              SubmenuButton(menuChildren: [
                item('AI araçları', () => c.setTool(EditorTool.ai), icon: Icons.auto_awesome),
                item('Otomatik iyileştir', c.autoAdjust, icon: Icons.auto_fix_high),
              ], child: const Text('AI')),
              SubmenuButton(menuChildren: [
                item('Klavye kısayolları', () => _showShortcuts(context), icon: Icons.keyboard),
                item('Hakkında', () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
                    icon: Icons.info_outline),
              ], child: const Text('Yardım')),
            ],
          ),
          ),
          Flexible(
            flex: 2,
            child: Text(
              '${c.info.name}${c.isDirty ? ' •' : ''}',
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 13, color: PxColors.muted),
            ),
          ),
          const SizedBox(width: 12),
          IconButton(tooltip: 'Geri al (Ctrl+Z)', onPressed: c.canUndo ? c.undo : null, icon: const Icon(Icons.undo, size: 20)),
          IconButton(tooltip: 'Yinele (Ctrl+Y)', onPressed: c.canRedo ? c.redo : null, icon: const Icon(Icons.redo, size: 20)),
          IconButton(tooltip: 'Kaydet (Ctrl+S)', onPressed: () => c.save(), icon: const Icon(Icons.save_outlined, size: 20)),
          const SizedBox(width: 6),
          FilledButton.icon(
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10)),
            onPressed: () => showExportDialog(context, c),
            icon: const Icon(Icons.ios_share, size: 18),
            label: const Text('Dışa aktar'),
          ),
          const SizedBox(width: 10),
        ],
      ),
    );
  }

  static const _railTools = [
    (EditorTool.select, Icons.near_me_outlined, 'Seç / Taşı (V)'),
    (EditorTool.crop, Icons.crop_rotate, 'Kırp ve döndür (C)'),
    (EditorTool.adjust, Icons.tune, 'Ayarlar'),
    (EditorTool.filters, Icons.filter_vintage_outlined, 'Filtreler'),
    (EditorTool.text, Icons.text_fields, 'Metin (T)'),
    (EditorTool.shapes, Icons.category_outlined, 'Şekiller'),
    (EditorTool.stickers, Icons.emoji_emotions_outlined, 'Çıkartmalar'),
    (EditorTool.mask, Icons.brush, 'Maske'),
    (EditorTool.ai, Icons.auto_awesome, 'AI araçları'),
  ];

  Widget _toolRail(EditorController c) {
    return Container(
      width: 60,
      color: PxColors.surface,
      child: Column(
        children: [
          const SizedBox(height: 8),
          for (final t in _railTools)
            _RailButton(
              icon: t.$2,
              tooltip: t.$3,
              selected: c.tool == t.$1 || (t.$1 == EditorTool.ai && c.tool == EditorTool.inpaint),
              onTap: () => c.setTool(t.$1),
            ),
          const Divider(indent: 12, endIndent: 12, height: 20),
          _RailButton(icon: Icons.add_photo_alternate_outlined, tooltip: 'Görsel katman ekle', selected: false, onTap: _addImageLayer),
          const Spacer(),
          _RailButton(
            icon: Icons.info_outline,
            tooltip: 'Hakkında',
            selected: false,
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage())),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _canvasArea(EditorController c) {
    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            // Tuvale tıklanınca odak metin alanından düzenleyiciye döner (kısayollar için).
            onPointerDown: (_) {
              if (!_rootFocus.hasPrimaryFocus) _rootFocus.requestFocus();
            },
            child: EditorCanvas(controller: c, viewport: _viewport),
          ),
        ),
        Positioned(top: 10, right: 10, child: RenderIndicator(controller: c)),
        if (c.tool == EditorTool.inpaint) Positioned(top: 10, left: 10, right: 10, child: _inpaintBar(c)),
      ],
    );
  }

  Widget _inpaintBar(EditorController c) {
    return Center(
      child: Material(
        color: const Color(0xEE171C2C),
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.healing, color: PxColors.danger, size: 18),
              const SizedBox(width: 8),
              Text('Silinecek alanı boyayın (${c.inpaintStrokes.length} darbe)', style: const TextStyle(fontSize: 12.5)),
              const SizedBox(width: 8),
              IconButton(tooltip: 'Son darbeyi geri al', onPressed: c.undoInpaintStroke, icon: const Icon(Icons.undo, size: 18)),
              IconButton(tooltip: 'Temizle', onPressed: c.clearInpaint, icon: const Icon(Icons.delete_sweep_outlined, size: 18)),
              TextButton(onPressed: () => c.setTool(EditorTool.ai), child: const Text('Bitti')),
            ],
          ),
        ),
      ),
    );
  }

  Widget _toolPanel(EditorController c, {bool mobile = false}) {
    switch (c.tool) {
      case EditorTool.crop:
        return CropPanel(controller: c, compact: mobile);
      case EditorTool.adjust:
        return AdjustPanel(controller: c);
      case EditorTool.filters:
        return FilterPanel(controller: c, horizontal: mobile);
      case EditorTool.text:
        return TextPanel(controller: c);
      case EditorTool.shapes:
        return ShapePanel(controller: c);
      case EditorTool.stickers:
        return StickerPanel(controller: c);
      case EditorTool.mask:
        return MaskPanel(controller: c);
      case EditorTool.ai:
      case EditorTool.inpaint:
        return AiPanel(controller: c);
      case EditorTool.layers:
        return LayersList(controller: c);
      case EditorTool.select:
        return LayerPropertiesPanel(controller: c);
    }
  }

  Widget _rightPanel(EditorController c) {
    return Container(
      color: PxColors.surface,
      child: Column(
        children: [
          Container(
            height: 40,
            alignment: Alignment.centerLeft,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Text(c.tool == EditorTool.inpaint ? EditorTool.ai.label : c.tool.label,
                style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13.5)),
          ),
          const Divider(),
          Expanded(flex: 6, child: _toolPanel(c)),
          const Divider(),
          Expanded(
            flex: 4,
            child: DefaultTabController(
              length: 2,
              child: Column(
                children: [
                  const TabBar(
                    tabs: [Tab(height: 36, text: 'Katmanlar'), Tab(height: 36, text: 'Geçmiş')],
                    labelStyle: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  Expanded(
                    child: TabBarView(children: [
                      LayersList(controller: c),
                      HistoryPanel(controller: c),
                    ]),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusBar(EditorController c) {
    return Container(
      height: 32,
      color: PxColors.surface,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: ListenableBuilder(
        listenable: _viewport,
        builder: (context, _) => Row(
          children: [
            Icon(c.isDirty ? Icons.circle : Icons.check_circle, size: 10, color: c.isDirty ? PxColors.warning : PxColors.success),
            const SizedBox(width: 6),
            Text(c.isDirty ? 'Kaydedilmemiş değişiklikler' : 'Kaydedildi', style: const TextStyle(fontSize: 12, color: PxColors.muted)),
            const SizedBox(width: 18),
            Text('${c.doc.canvasWidth} × ${c.doc.canvasHeight} px • ${formatMegapixels(c.doc.canvasWidth, c.doc.canvasHeight)}',
                style: const TextStyle(fontSize: 12, color: PxColors.muted)),
            const SizedBox(width: 18),
            Text('${c.doc.layers.length} katman • ${c.history.length} adım geçmiş', style: const TextStyle(fontSize: 12, color: PxColors.muted)),
            const Spacer(),
            IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Uzaklaştır',
                onPressed: () => _viewport.zoomBy(0.8),
                icon: const Icon(Icons.remove, size: 16)),
            SizedBox(
              width: 58,
              child: Text('%${_viewport.zoomPercent.round()}',
                  textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontFeatures: [FontFeature.tabularFigures()])),
            ),
            IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Yakınlaştır',
                onPressed: () => _viewport.zoomBy(1.25),
                icon: const Icon(Icons.add, size: 16)),
            TextButton(onPressed: _viewport.fit, child: const Text('Sığdır', style: TextStyle(fontSize: 12))),
            TextButton(onPressed: _viewport.actualPixels, child: const Text('%100', style: TextStyle(fontSize: 12))),
          ],
        ),
      ),
    );
  }

  void _showShortcuts(BuildContext context) {
    const items = [
      ('Ctrl + Z', 'Geri al'),
      ('Ctrl + Y / Ctrl + Shift + Z', 'Yinele'),
      ('Ctrl + S', 'Projeyi kaydet'),
      ('Ctrl + E', 'Dışa aktar'),
      ('Ctrl + D', 'Seçili katmanı çoğalt'),
      ('Delete', 'Seçili katmanı sil'),
      ('Ctrl + 0', 'Ekrana sığdır'),
      ('Ctrl + 1', 'Gerçek boyut (%100)'),
      ('Ctrl + + / Ctrl + -', 'Yakınlaştır / uzaklaştır'),
      ('Fare tekerleği', 'İmleç noktasına yakınlaştır'),
      ('Orta/sağ tık + sürükle', 'Görünümü kaydır'),
      ('V / C / T', 'Seç, Kırp, Metin araçları'),
      ('Enter / Esc', 'Kırpmayı uygula / iptal et'),
    ];
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Klavye kısayolları'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final i in items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(children: [
                    SizedBox(width: 190, child: Text(i.$1, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13))),
                    Expanded(child: Text(i.$2, style: const TextStyle(fontSize: 13))),
                  ]),
                ),
            ],
          ),
        ),
        actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Tamam'))],
      ),
    );
  }

  // ================================================================ Mobil

  static const _mobileTools = [
    (EditorTool.crop, Icons.crop_rotate, 'Kırp'),
    (EditorTool.adjust, Icons.tune, 'Ayarlar'),
    (EditorTool.filters, Icons.filter_vintage_outlined, 'Filtre'),
    (EditorTool.ai, Icons.auto_awesome, 'AI'),
    (EditorTool.text, Icons.text_fields, 'Metin'),
    (EditorTool.stickers, Icons.emoji_emotions_outlined, 'Çıkartma'),
    (EditorTool.shapes, Icons.category_outlined, 'Şekil'),
    (EditorTool.mask, Icons.brush, 'Maske'),
    (EditorTool.layers, Icons.layers_outlined, 'Katmanlar'),
  ];

  Widget _mobile(EditorController c) {
    final panelVisible = _mobilePanelOpen && c.tool != EditorTool.select || (c.tool == EditorTool.select && c.selectedLayer != null && _mobilePanelOpen);
    final height = MediaQuery.sizeOf(context).height;
    final panelHeight = c.tool == EditorTool.filters ? 150.0 : (height * 0.38).clamp(220.0, 360.0);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _handlePop, tooltip: 'Geri'),
        titleSpacing: 0,
        title: GestureDetector(
          onTap: _rename,
          child: Text('${c.info.name}${c.isDirty ? ' •' : ''}', overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 16)),
        ),
        actions: [
          IconButton(tooltip: 'Geri al', onPressed: c.canUndo ? c.undo : null, icon: const Icon(Icons.undo)),
          IconButton(tooltip: 'Yinele', onPressed: c.canRedo ? c.redo : null, icon: const Icon(Icons.redo)),
          IconButton(tooltip: 'Kaydet', onPressed: () => c.save(), icon: const Icon(Icons.save_outlined)),
          IconButton(tooltip: 'Dışa aktar', onPressed: () => showExportDialog(context, c), icon: const Icon(Icons.ios_share)),
          PopupMenuButton<String>(
            onSelected: (v) {
              switch (v) {
                case 'image':
                  _addImageLayer();
                case 'history':
                  showModalBottomSheet<void>(
                    context: context,
                    builder: (_) => SizedBox(height: 420, child: HistoryPanel(controller: c)),
                  );
                case 'rename':
                  _rename();
                case 'about':
                  Navigator.of(context).push(MaterialPageRoute(builder: (_) => const AboutPage()));
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'image', child: Text('Görsel katman ekle')),
              PopupMenuItem(value: 'history', child: Text('Düzenleme geçmişi')),
              PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
              PopupMenuItem(value: 'about', child: Text('Hakkında')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(child: _canvasArea(c)),
            AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              height: panelVisible ? panelHeight : 0,
              decoration: const BoxDecoration(
                color: PxColors.surface,
                border: Border(top: BorderSide(color: PxColors.border)),
              ),
              child: panelVisible
                  ? Column(
                      children: [
                        SizedBox(
                          height: 34,
                          child: Row(
                            children: [
                              const SizedBox(width: 14),
                              Text(c.tool == EditorTool.select ? 'Katman özellikleri' : c.tool.label,
                                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                              const Spacer(),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.keyboard_arrow_down),
                                onPressed: () => setState(() => _mobilePanelOpen = false),
                              ),
                            ],
                          ),
                        ),
                        Expanded(child: _toolPanel(c, mobile: true)),
                      ],
                    )
                  : null,
            ),
            Container(
              height: 64,
              decoration: const BoxDecoration(
                color: PxColors.surface,
                border: Border(top: BorderSide(color: PxColors.border)),
              ),
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 6),
                children: [
                  if (c.selectedLayer != null)
                    _MobileToolButton(
                      icon: Icons.edit_note,
                      label: 'Özellikler',
                      selected: c.tool == EditorTool.select && _mobilePanelOpen,
                      onTap: () {
                        c.setTool(EditorTool.select);
                        setState(() => _mobilePanelOpen = true);
                      },
                    ),
                  for (final t in _mobileTools)
                    _MobileToolButton(
                      icon: t.$2,
                      label: t.$3,
                      selected: c.tool == t.$1 || (t.$1 == EditorTool.ai && c.tool == EditorTool.inpaint),
                      onTap: () {
                        if (c.tool == t.$1 && _mobilePanelOpen) {
                          setState(() => _mobilePanelOpen = false);
                          if (t.$1 != EditorTool.crop) c.setTool(EditorTool.select);
                        } else {
                          c.setTool(t.$1);
                          setState(() => _mobilePanelOpen = true);
                        }
                      },
                    ),
                  _MobileToolButton(icon: Icons.add_photo_alternate_outlined, label: 'Görsel', selected: false, onTap: _addImageLayer),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailButton extends StatelessWidget {
  const _RailButton({required this.icon, required this.tooltip, required this.selected, required this.onTap});
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Tooltip(
        message: tooltip,
        preferBelow: false,
        child: Material(
          color: selected ? PxColors.primary.withOpacity(0.22) : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: onTap,
            child: SizedBox(
              width: 44,
              height: 44,
              child: Icon(icon, size: 21, color: selected ? PxColors.text : PxColors.muted),
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileToolButton extends StatelessWidget {
  const _MobileToolButton({required this.icon, required this.label, required this.selected, required this.onTap});
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: SizedBox(
        width: 68,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: selected ? PxColors.accent : PxColors.text),
            const SizedBox(height: 3),
            Text(label,
                style: TextStyle(fontSize: 11, color: selected ? PxColors.accent : PxColors.muted), overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
