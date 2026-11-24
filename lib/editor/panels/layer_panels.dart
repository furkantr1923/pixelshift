import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../layers/layer.dart';
import '../editor_controller.dart';

const List<String> kFonts = [
  'Inter',
  'Poppins',
  'Fira Sans',
  'Anton',
  'Archivo Black',
  'Crimson Text',
  'Comic Relief',
  'Anonymous Pro',
];

IconData layerIcon(Layer l) {
  if (l is TextLayer) return l.isSticker ? Icons.emoji_emotions_outlined : Icons.text_fields;
  if (l is ImageLayer) return Icons.image_outlined;
  return Icons.category_outlined;
}

/// Katman listesi: üstteki katman en üstte gösterilir.
class LayersList extends StatelessWidget {
  const LayersList({super.key, required this.controller, this.onLayerTap});
  final EditorController controller;
  final VoidCallback? onLayerTap;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final layers = controller.doc.layers;
        final n = layers.length;
        return Column(
          children: [
            Expanded(
              child: n == 0
                  ? const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: Text('Henüz katman yok.\nMetin, şekil, çıkartma veya görsel ekleyin.',
                            textAlign: TextAlign.center, style: TextStyle(color: PxColors.muted, fontSize: 12.5)),
                      ),
                    )
                  : ReorderableListView.builder(
                      buildDefaultDragHandles: false,
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      itemCount: n,
                      onReorder: (oldIndex, newIndex) {
                        // Görünüm ters sıralı: görünüm indeksini belge indeksine çevir.
                        if (newIndex > oldIndex) newIndex--;
                        final from = n - 1 - oldIndex;
                        final to = n - 1 - newIndex;
                        controller.reorderLayers(from, to);
                      },
                      itemBuilder: (context, i) {
                        final l = layers[n - 1 - i];
                        return _LayerRow(
                          key: ValueKey(l.id),
                          index: i,
                          layer: l,
                          controller: controller,
                          selected: l.id == controller.selectedLayerId,
                          onTap: () {
                            controller.selectLayer(l.id);
                            if (controller.tool != EditorTool.mask) controller.setTool(EditorTool.select);
                            onLayerTap?.call();
                          },
                        );
                      },
                    ),
            ),
            const Divider(),
            ListTile(
              dense: true,
              leading: const Icon(Icons.photo_outlined, size: 20, color: PxColors.muted),
              title: const Text('Arka plan (fotoğraf)', style: TextStyle(fontSize: 13)),
              subtitle: Text('${controller.doc.canvasWidth} × ${controller.doc.canvasHeight} px',
                  style: const TextStyle(fontSize: 11.5, color: PxColors.muted)),
              trailing: const Icon(Icons.lock_outline, size: 16, color: PxColors.muted),
              onTap: () => controller.selectLayer(null),
            ),
          ],
        );
      },
    );
  }
}

class _LayerRow extends StatelessWidget {
  const _LayerRow({
    super.key,
    required this.index,
    required this.layer,
    required this.controller,
    required this.selected,
    required this.onTap,
  });

  final int index;
  final Layer layer;
  final EditorController controller;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l = layer;
    return Material(
      color: selected ? PxColors.primary.withOpacity(0.16) : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          child: Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(6),
                  child: Icon(Icons.drag_indicator, size: 18, color: PxColors.muted),
                ),
              ),
              Icon(layerIcon(l), size: 18, color: l.visible ? PxColors.text : PxColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 13, color: l.visible ? PxColors.text : PxColors.muted)),
                    Text(
                      [
                        l.typeLabel,
                        if (l.blend != LayerBlend.normal) l.blend.label,
                        if (l.opacity < 0.999) '%${(l.opacity * 100).round()}',
                        if (l.mask.isNotEmpty) 'maske',
                      ].join(' · '),
                      style: const TextStyle(fontSize: 11, color: PxColors.muted),
                    ),
                  ],
                ),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l.visible ? 'Gizle' : 'Göster',
                icon: Icon(l.visible ? Icons.visibility_outlined : Icons.visibility_off_outlined, size: 18),
                onPressed: () => controller.toggleVisibility(l.id),
              ),
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: l.locked ? 'Kilidi aç' : 'Kilitle',
                icon: Icon(l.locked ? Icons.lock : Icons.lock_open_outlined, size: 17),
                onPressed: () => controller.toggleLock(l.id),
              ),
              PopupMenuButton<String>(
                tooltip: 'Diğer',
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (v) async {
                  switch (v) {
                    case 'dup':
                      controller.duplicateLayer(l.id);
                    case 'rename':
                      final name = await promptText(context, title: 'Katmanı yeniden adlandır', initial: l.name, label: 'Ad');
                      if (name != null) controller.renameLayer(l.id, name);
                    case 'center':
                      controller.centerLayer(l.id);
                    case 'up':
                      controller.moveLayer(l.id, 1);
                    case 'down':
                      controller.moveLayer(l.id, -1);
                    case 'delete':
                      controller.deleteLayer(l.id);
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'dup', child: Text('Çoğalt')),
                  PopupMenuItem(value: 'rename', child: Text('Yeniden adlandır')),
                  PopupMenuItem(value: 'center', child: Text('Tuvalde ortala')),
                  PopupMenuItem(value: 'up', child: Text('Bir öne getir')),
                  PopupMenuItem(value: 'down', child: Text('Bir arkaya gönder')),
                  PopupMenuItem(value: 'delete', child: Text('Sil', style: TextStyle(color: PxColors.danger))),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Seçili katmanın özellikleri.
class LayerPropertiesPanel extends StatelessWidget {
  const LayerPropertiesPanel({super.key, required this.controller, this.embedded = false});
  final EditorController controller;

  /// true ise kaydırılabilir liste yerine sütun döndürür (başka bir listenin içinde).
  final bool embedded;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final l = controller.selectedLayer;
        if (l == null) {
          if (embedded) return const SizedBox.shrink();
          return const Center(
            child: Padding(
              padding: EdgeInsets.all(20),
              child: Text(
                'Düzenlemek için tuvalde bir katmana dokunun\nveya soldaki araçlardan birini seçin.',
                textAlign: TextAlign.center,
                style: TextStyle(color: PxColors.muted, fontSize: 13),
              ),
            ),
          );
        }
        final children = [
          if (l is TextLayer) TextLayerEditor(key: ValueKey('text-${l.id}'), controller: controller, layer: l),
          if (l is ImageLayer) _ImageProps(controller: controller, layer: l),
          if (l is ShapeLayer) _ShapeProps(controller: controller, layer: l),
          _CommonProps(controller: controller, layer: l),
        ];
        if (embedded) return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children);
        return ListView(padding: const EdgeInsets.only(bottom: 16), children: children);
      },
    );
  }
}

class _CommonProps extends StatelessWidget {
  const _CommonProps({required this.controller, required this.layer});
  final EditorController controller;
  final Layer layer;

  @override
  Widget build(BuildContext context) {
    final l = layer;
    final deg = (l.rotation * 180 / math.pi + 540) % 360 - 180;
    return PanelSection(
      title: 'Katman',
      children: [
        LabeledSlider(
          label: 'Opaklık',
          value: l.opacity * 100,
          min: 0,
          max: 100,
          defaultValue: 100,
          suffix: '%',
          onChanged: (v) => controller.previewLayer(l.copyBase(opacity: v / 100)),
          onChangeEnd: (v) => controller.updateLayer(l.copyBase(opacity: v / 100), 'Opaklık'),
        ),
        LabeledSlider(
          label: 'Döndürme',
          value: deg,
          min: -180,
          max: 180,
          suffix: '°',
          onChanged: (v) => controller.previewLayer(l.copyBase(rotation: v * math.pi / 180)),
          onChangeEnd: (v) => controller.updateLayer(l.copyBase(rotation: v * math.pi / 180), 'Döndürme'),
        ),
        LabeledSlider(
          label: 'Ölçek',
          value: (l.scale * 100).clamp(5, 400).toDouble(),
          min: 5,
          max: 400,
          defaultValue: 100,
          suffix: '%',
          onChanged: (v) => controller.previewLayer(l.copyBase(scale: v / 100)),
          onChangeEnd: (v) => controller.updateLayer(l.copyBase(scale: v / 100), 'Ölçek'),
        ),
        const SizedBox(height: 4),
        DropdownButtonFormField<LayerBlend>(
          value: l.blend,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Karışım modu'),
          items: [for (final b in LayerBlend.values) DropdownMenuItem(value: b, child: Text(b.label))],
          onChanged: (b) {
            if (b != null) controller.updateLayer(l.copyBase(blend: b), 'Karışım modu');
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            PxChip(label: 'Ortala', icon: Icons.center_focus_strong, selected: false, onTap: () => controller.centerLayer(l.id)),
            PxChip(label: 'Çoğalt', icon: Icons.copy, selected: false, onTap: () => controller.duplicateLayer(l.id)),
            PxChip(label: 'Öne', icon: Icons.flip_to_front, selected: false, onTap: () => controller.moveLayer(l.id, 1)),
            PxChip(label: 'Arkaya', icon: Icons.flip_to_back, selected: false, onTap: () => controller.moveLayer(l.id, -1)),
            PxChip(label: 'Maske', icon: Icons.brush, selected: false, onTap: () => controller.setTool(EditorTool.mask)),
            PxChip(label: 'Sil', icon: Icons.delete_outline, selected: false, onTap: () => controller.deleteLayer(l.id)),
          ],
        ),
      ],
    );
  }
}

/// Metin katmanı düzenleyicisi (yazarken canlı önizleme, kısa beklemeden sonra geçmişe kayıt).
class TextLayerEditor extends StatefulWidget {
  const TextLayerEditor({super.key, required this.controller, required this.layer});
  final EditorController controller;
  final TextLayer layer;

  @override
  State<TextLayerEditor> createState() => _TextLayerEditorState();
}

class _TextLayerEditorState extends State<TextLayerEditor> {
  late final TextEditingController _text = TextEditingController(text: widget.layer.text);
  Timer? _commitTimer;

  @override
  void didUpdateWidget(TextLayerEditor old) {
    super.didUpdateWidget(old);
    if (widget.layer.text != _text.text && !_isTyping) {
      _text.text = widget.layer.text;
    }
  }

  bool get _isTyping => _commitTimer?.isActive ?? false;

  @override
  void dispose() {
    if (_isTyping) {
      _commitTimer?.cancel();
      final c = widget.controller;
      // Ağaç kilitliyken bildirim yapılmaması için bir sonraki mikro göreve ertelenir.
      Future.microtask(() => c.commit('Metni düzenle'));
    }
    _text.dispose();
    super.dispose();
  }

  TextLayer get l => widget.controller.selectedLayer is TextLayer ? widget.controller.selectedLayer! as TextLayer : widget.layer;

  void _update(TextLayer t, String label) => widget.controller.updateLayer(t, label);

  @override
  Widget build(BuildContext context) {
    final layer = l;
    final c = widget.controller;
    return PanelSection(
      title: layer.isSticker ? 'Çıkartma' : 'Metin',
      children: [
        TextField(
          controller: _text,
          minLines: 1,
          maxLines: 5,
          decoration: const InputDecoration(labelText: 'Metin'),
          onChanged: (v) {
            c.previewLayer(l.copyWith(text: v));
            _commitTimer?.cancel();
            _commitTimer = Timer(const Duration(milliseconds: 700), () => c.commit('Metni düzenle'));
          },
        ),
        const SizedBox(height: 10),
        if (!layer.isSticker)
          DropdownButtonFormField<String>(
            value: kFonts.contains(layer.fontFamily) ? layer.fontFamily : kFonts.first,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Yazı tipi'),
            items: [
              for (final f in kFonts)
                DropdownMenuItem(value: f, child: Text(f, style: TextStyle(fontFamily: f))),
            ],
            onChanged: (f) {
              if (f != null) _update(layer.copyWith(fontFamily: f), 'Yazı tipi');
            },
          ),
        const SizedBox(height: 6),
        LabeledSlider(
          label: 'Boyut',
          value: layer.fontSize,
          min: 8,
          max: math.max(400.0, layer.fontSize),
          defaultValue: layer.fontSize,
          suffix: ' px',
          onChanged: (v) => c.previewLayer(layer.copyWith(fontSize: v)),
          onChangeEnd: (v) => _update(layer.copyWith(fontSize: v), 'Yazı boyutu'),
        ),
        if (!layer.isSticker) ...[
          Row(
            children: [
              ColorButton(color: layer.color, label: 'Renk', onChanged: (v) => _update(layer.copyWith(color: v), 'Yazı rengi')),
              const Spacer(),
              _toggle(Icons.format_bold, 'Kalın', layer.bold, () => _update(layer.copyWith(bold: !layer.bold), 'Kalın')),
              _toggle(Icons.format_italic, 'İtalik', layer.italic, () => _update(layer.copyWith(italic: !layer.italic), 'İtalik')),
              const SizedBox(width: 6),
              _toggle(Icons.format_align_left, 'Sola', layer.align == TextAlignOption.left,
                  () => _update(layer.copyWith(align: TextAlignOption.left), 'Hizalama')),
              _toggle(Icons.format_align_center, 'Ortala', layer.align == TextAlignOption.center,
                  () => _update(layer.copyWith(align: TextAlignOption.center), 'Hizalama')),
              _toggle(Icons.format_align_right, 'Sağa', layer.align == TextAlignOption.right,
                  () => _update(layer.copyWith(align: TextAlignOption.right), 'Hizalama')),
            ],
          ),
          LabeledSlider(
            label: 'Harf aralığı',
            value: layer.letterSpacing,
            min: -10,
            max: math.max(60.0, layer.letterSpacing),
            onChanged: (v) => c.previewLayer(layer.copyWith(letterSpacing: v)),
            onChangeEnd: (v) => _update(layer.copyWith(letterSpacing: v), 'Harf aralığı'),
          ),
          LabeledSlider(
            label: 'Satır yüksekliği',
            value: layer.lineHeight,
            min: 0.7,
            max: 3,
            defaultValue: 1.2,
            decimals: 2,
            onChanged: (v) => c.previewLayer(layer.copyWith(lineHeight: v)),
            onChangeEnd: (v) => _update(layer.copyWith(lineHeight: v), 'Satır yüksekliği'),
          ),
          LabeledSlider(
            label: 'Kutu genişliği (0 = otomatik)',
            value: layer.boxWidth,
            min: 0,
            max: math.max(c.doc.canvasWidth.toDouble(), layer.boxWidth),
            onChanged: (v) => c.previewLayer(layer.copyWith(boxWidth: v < 20 ? 0 : v)),
            onChangeEnd: (v) => _update(layer.copyWith(boxWidth: v < 20 ? 0 : v), 'Metin kutusu'),
          ),
          const Divider(height: 20),
          Row(
            children: [
              const Expanded(child: Text('Kontur', style: TextStyle(fontSize: 13))),
              ColorButton(color: layer.strokeColor, onChanged: (v) => _update(layer.copyWith(strokeColor: v), 'Kontur rengi')),
            ],
          ),
          LabeledSlider(
            label: 'Kontur kalınlığı',
            value: layer.strokeWidth,
            min: 0,
            max: math.max(40.0, layer.strokeWidth),
            onChanged: (v) => c.previewLayer(layer.copyWith(strokeWidth: v)),
            onChangeEnd: (v) => _update(layer.copyWith(strokeWidth: v), 'Kontur'),
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            title: const Text('Gölge', style: TextStyle(fontSize: 13)),
            value: layer.shadow,
            onChanged: (v) => _update(layer.copyWith(shadow: v), 'Gölge'),
          ),
          Row(
            children: [
              const Expanded(child: Text('Arka plan kutusu', style: TextStyle(fontSize: 13))),
              ColorButton(
                color: layer.background,
                allowTransparent: true,
                onChanged: (v) => _update(layer.copyWith(background: v, padding: v != 0 && layer.padding == 0 ? layer.fontSize * 0.35 : null), 'Metin arka planı'),
              ),
            ],
          ),
          if (layer.background != 0)
            LabeledSlider(
              label: 'İç boşluk',
              value: layer.padding,
              min: 0,
              max: math.max(120.0, layer.padding),
              onChanged: (v) => c.previewLayer(layer.copyWith(padding: v)),
              onChangeEnd: (v) => _update(layer.copyWith(padding: v), 'İç boşluk'),
            ),
        ],
      ],
    );
  }

  Widget _toggle(IconData icon, String tip, bool on, VoidCallback onTap) {
    return IconButton(
      tooltip: tip,
      visualDensity: VisualDensity.compact,
      isSelected: on,
      style: IconButton.styleFrom(backgroundColor: on ? PxColors.primary.withOpacity(0.25) : null),
      icon: Icon(icon, size: 18),
      onPressed: onTap,
    );
  }
}

class _ImageProps extends StatelessWidget {
  const _ImageProps({required this.controller, required this.layer});
  final EditorController controller;
  final ImageLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = layer;
    final c = controller;
    final maxRadius = math.min(l.width, l.height) / 2;
    return PanelSection(
      title: 'Görsel',
      children: [
        LabeledSlider(
          label: 'Köşe yuvarlama',
          value: l.cornerRadius.clamp(0, maxRadius).toDouble(),
          min: 0,
          max: maxRadius,
          onChanged: (v) => c.previewLayer(l.copyWith(cornerRadius: v)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(cornerRadius: v), 'Köşe yuvarlama'),
        ),
        Row(
          children: [
            const Expanded(child: Text('Çerçeve', style: TextStyle(fontSize: 13))),
            ColorButton(color: l.borderColor, onChanged: (v) => c.updateLayer(l.copyWith(borderColor: v), 'Çerçeve rengi')),
          ],
        ),
        LabeledSlider(
          label: 'Çerçeve kalınlığı',
          value: l.borderWidth,
          min: 0,
          max: math.max(80.0, l.borderWidth),
          onChanged: (v) => c.previewLayer(l.copyWith(borderWidth: v)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(borderWidth: v), 'Çerçeve'),
        ),
        LabeledSlider(
          label: 'İçerik yakınlaştırma',
          value: l.contentScale * 100,
          min: 100,
          max: 400,
          defaultValue: 100,
          suffix: '%',
          onChanged: (v) => c.previewLayer(l.copyWith(contentScale: v / 100)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(contentScale: v / 100), 'İçerik yakınlaştırma'),
        ),
        LabeledSlider(
          label: 'İçerik yatay konum',
          value: l.contentOffsetX * 100,
          min: -100,
          max: 100,
          onChanged: (v) => c.previewLayer(l.copyWith(contentOffsetX: v / 100)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(contentOffsetX: v / 100), 'İçerik konumu'),
        ),
        LabeledSlider(
          label: 'İçerik dikey konum',
          value: l.contentOffsetY * 100,
          min: -100,
          max: 100,
          onChanged: (v) => c.previewLayer(l.copyWith(contentOffsetY: v / 100)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(contentOffsetY: v / 100), 'İçerik konumu'),
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            icon: const Icon(Icons.aspect_ratio, size: 18),
            label: const Text('Kutuyu görsel oranına getir'),
            onPressed: () => c.updateLayer(
              l.copyWith(height: l.width * l.assetHeight / math.max(1.0, l.assetWidth), contentScale: 1, contentOffsetX: 0, contentOffsetY: 0),
              'Görsel oranı',
            ),
          ),
        ),
      ],
    );
  }
}

class _ShapeProps extends StatelessWidget {
  const _ShapeProps({required this.controller, required this.layer});
  final EditorController controller;
  final ShapeLayer layer;

  @override
  Widget build(BuildContext context) {
    final l = layer;
    final c = controller;
    final maxSide = math.max(c.doc.canvasWidth, c.doc.canvasHeight).toDouble() * 1.5;
    return PanelSection(
      title: 'Şekil',
      children: [
        DropdownButtonFormField<ShapeKind>(
          value: l.shape,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Şekil türü'),
          items: [for (final s in ShapeKind.values) DropdownMenuItem(value: s, child: Text(s.label))],
          onChanged: (s) {
            if (s != null) c.updateLayer(l.copyWith(shape: s), 'Şekil türü');
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ColorButton(color: l.fill, label: 'Dolgu', allowTransparent: true, onChanged: (v) => c.updateLayer(l.copyWith(fill: v), 'Dolgu rengi')),
            const Spacer(),
            ColorButton(
              color: l.fillEnd,
              label: 'Geçiş',
              allowTransparent: true,
              onChanged: (v) => c.updateLayer(l.copyWith(fillEnd: v), 'Renk geçişi'),
            ),
          ],
        ),
        Row(
          children: [
            ColorButton(color: l.stroke, label: 'Kontur', allowTransparent: true, onChanged: (v) => c.updateLayer(l.copyWith(stroke: v, strokeWidth: l.strokeWidth == 0 ? 6 : null), 'Kontur rengi')),
          ],
        ),
        LabeledSlider(
          label: 'Kontur kalınlığı',
          value: l.strokeWidth,
          min: 0,
          max: math.max(60.0, l.strokeWidth),
          onChanged: (v) => c.previewLayer(l.copyWith(strokeWidth: v)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(strokeWidth: v), 'Kontur'),
        ),
        if (l.shape == ShapeKind.roundRect || l.shape == ShapeKind.bubble)
          LabeledSlider(
            label: 'Köşe yuvarlama',
            value: l.cornerRadius,
            min: 0,
            max: math.max(math.min(l.width, l.height) / 2, l.cornerRadius),
            onChanged: (v) => c.previewLayer(l.copyWith(cornerRadius: v)),
            onChangeEnd: (v) => c.updateLayer(l.copyWith(cornerRadius: v), 'Köşe yuvarlama'),
          ),
        LabeledSlider(
          label: 'Genişlik',
          value: l.width,
          min: 2,
          max: math.max(maxSide, l.width),
          defaultValue: l.width,
          onChanged: (v) => c.previewLayer(l.copyWith(width: v)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(width: v), 'Genişlik'),
        ),
        LabeledSlider(
          label: 'Yükseklik',
          value: l.height,
          min: 2,
          max: math.max(maxSide, l.height),
          defaultValue: l.height,
          onChanged: (v) => c.previewLayer(l.copyWith(height: v)),
          onChangeEnd: (v) => c.updateLayer(l.copyWith(height: v), 'Yükseklik'),
        ),
      ],
    );
  }
}
