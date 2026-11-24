import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../layers/layer.dart';
import '../../layers/layer_painter.dart';
import '../editor_controller.dart';
import 'layer_panels.dart';

/// Metin ekleme hazır ayarları + seçili metnin özellikleri.
class TextPanel extends StatelessWidget {
  const TextPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sel = controller.selectedLayer;
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            PanelSection(title: 'Metin ekle', children: [
              _preset('Başlık', 'Başlık', 0.09, true, 'Anton', 30),
              _preset('Alt başlık', 'Alt başlık', 0.055, true, 'Poppins', 20),
              _preset('Gövde metni', 'Metninizi buraya yazın', 0.035, false, 'Inter', 15),
              _preset('Alıntı', '“Güzel bir söz”', 0.05, false, 'Crimson Text', 20),
              _preset('El yazısı tarzı', 'Merhaba!', 0.06, true, 'Comic Relief', 20),
            ]),
            if (sel is TextLayer && !sel.isSticker)
              TextLayerEditor(key: ValueKey('tp-${sel.id}'), controller: controller, layer: sel),
          ],
        );
      },
    );
  }

  Widget _preset(String label, String text, double size, bool bold, String font, double previewSize) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(alignment: Alignment.centerLeft, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12)),
        onPressed: () => controller.addText(text: text, sizeFactor: size, bold: bold, font: font),
        child: Text(label,
            style: TextStyle(fontFamily: font, fontSize: previewSize, fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
      ),
    );
  }
}

/// Şekil ve grafik öğeleri.
class ShapePanel extends StatelessWidget {
  const ShapePanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final sel = controller.selectedLayer;
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            PanelSection(title: 'Şekil ekle', children: [
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final k in ShapeKind.values)
                    Tooltip(
                      message: k.label,
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => controller.addShape(k),
                        child: Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: PxColors.surface3,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: PxColors.border),
                          ),
                          padding: const EdgeInsets.all(12),
                          child: CustomPaint(painter: _ShapeIconPainter(k)),
                        ),
                      ),
                    ),
                ],
              ),
            ]),
            if (sel is ShapeLayer) LayerPropertiesPanel(controller: controller, embedded: true),
          ],
        );
      },
    );
  }
}

class _ShapeIconPainter extends CustomPainter {
  _ShapeIconPainter(this.kind);
  final ShapeKind kind;

  @override
  void paint(Canvas canvas, Size size) {
    var r = Offset.zero & size;
    if (kind == ShapeKind.line) r = Rect.fromCenter(center: r.center, width: size.width, height: 4);
    if (kind == ShapeKind.arrow) r = Rect.fromCenter(center: r.center, width: size.width, height: size.height * 0.6);
    final path = LayerPainter.shapePath(kind, r, 8);
    canvas.drawPath(path, Paint()..color = PxColors.primary);
  }

  @override
  bool shouldRepaint(_ShapeIconPainter old) => old.kind != kind;
}

/// Emoji çıkartmaları (platformun emoji yazı tipiyle çizilir).
class StickerPanel extends StatelessWidget {
  const StickerPanel({super.key, required this.controller});
  final EditorController controller;

  static const Map<String, List<String>> groups = {
    'Popüler': ['😀', '😂', '😍', '😎', '🥳', '😇', '🤩', '😢', '😡', '👍', '👏', '🙏', '💪', '✌️', '🔥', '✨'],
    'Kalpler': ['❤️', '🧡', '💛', '💚', '💙', '💜', '🖤', '🤍', '💖', '💕', '💯', '💥'],
    'Doğa': ['🌸', '🌻', '🌹', '🍀', '🌈', '☀️', '🌙', '⭐', '❄️', '🌊', '🌴', '🍁'],
    'Etkinlik': ['🎉', '🎂', '🎁', '🎈', '🏆', '🎓', '📸', '🎵', '⚽', '🏀', '✈️', '🚗'],
    'İşaretler': ['✅', '❌', '⚠️', '❗', '❓', '➡️', '⬅️', '⬆️', '⬇️', '📍', '🔔', '💡'],
  };

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 16),
      children: [
        for (final g in groups.entries)
          PanelSection(title: g.key, children: [
            Wrap(
              spacing: 4,
              runSpacing: 4,
              children: [
                for (final e in g.value)
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () => controller.addSticker(e),
                    child: SizedBox(width: 46, height: 46, child: Center(child: Text(e, style: const TextStyle(fontSize: 28)))),
                  ),
              ],
            ),
          ]),
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 14),
          child: InfoBox(text: 'Emojiler cihazın emoji yazı tipiyle çizilir; Windows ve Android\'de görünümleri farklı olabilir.'),
        ),
      ],
    );
  }
}

/// Katman maskesi: fırça gizler, silgi geri açar.
class MaskPanel extends StatelessWidget {
  const MaskPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final l = controller.selectedLayer;
        if (l == null) {
          return const Padding(
            padding: EdgeInsets.all(16),
            child: InfoBox(text: 'Maske bir katmana uygulanır. Önce Katmanlar listesinden bir katman seçin '
                '(fotoğrafın bir bölümünü maskelemek için fotoğrafı görsel katman olarak ekleyebilirsiniz).'),
          );
        }
        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            PanelSection(title: 'Maske — ${l.name}', children: [
              Row(
                children: [
                  Expanded(
                    child: PxChip(
                      label: 'Fırça · gizle',
                      icon: Icons.brush,
                      selected: controller.maskHide,
                      onTap: () => controller.setMaskSettings(hide: true),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: PxChip(
                      label: 'Silgi · göster',
                      icon: Icons.auto_fix_normal,
                      selected: !controller.maskHide,
                      onTap: () => controller.setMaskSettings(hide: false),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              LabeledSlider(
                label: 'Fırça boyutu',
                value: controller.maskBrush,
                min: 2,
                max: 400,
                defaultValue: 40,
                suffix: ' px',
                onChanged: (v) => controller.setMaskSettings(brush: v),
              ),
              LabeledSlider(
                label: 'Kenar yumuşatma',
                value: controller.maskFeather * 100,
                min: 0,
                max: 100,
                defaultValue: 50,
                suffix: '%',
                onChanged: (v) => controller.setMaskSettings(feather: v / 100),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Maskeyi göster (kırmızı)', style: TextStyle(fontSize: 13)),
                value: controller.showMaskOverlay,
                onChanged: (v) => controller.setMaskSettings(overlay: v),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Maske etkin', style: TextStyle(fontSize: 13)),
                value: l.maskEnabled,
                onChanged: controller.setMaskEnabled,
              ),
              const SizedBox(height: 4),
              OutlinedButton.icon(
                onPressed: l.mask.isEmpty ? null : controller.clearMask,
                icon: const Icon(Icons.layers_clear_outlined, size: 18),
                label: Text('Maskeyi temizle (${l.mask.length} darbe)'),
              ),
            ]),
          ],
        );
      },
    );
  }
}

/// Düzenleme geçmişi (tıklanan adıma gider).
class HistoryPanel extends StatelessWidget {
  const HistoryPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final labels = controller.history.labels;
        final current = controller.history.index;
        return ListView.builder(
          itemCount: labels.length,
          itemBuilder: (context, i) {
            final idx = labels.length - 1 - i;
            final active = idx == current;
            final future = idx > current;
            return ListTile(
              dense: true,
              selected: active,
              selectedTileColor: PxColors.primary.withOpacity(0.15),
              leading: Icon(active ? Icons.radio_button_checked : Icons.history, size: 16,
                  color: future ? PxColors.border : (active ? PxColors.accent : PxColors.muted)),
              title: Text(labels[idx],
                  style: TextStyle(fontSize: 12.5, color: future ? PxColors.muted : PxColors.text)),
              onTap: () => controller.jumpTo(idx),
            );
          },
        );
      },
    );
  }
}
