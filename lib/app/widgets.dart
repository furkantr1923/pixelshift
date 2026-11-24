import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';

/// Panel başlığı + içerik.
class PanelSection extends StatelessWidget {
  const PanelSection({super.key, required this.title, required this.children, this.trailing, this.padding});

  final String title;
  final List<Widget> children;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? const EdgeInsets.fromLTRB(14, 12, 14, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title.toUpperCase(),
                  style: const TextStyle(fontSize: 11, letterSpacing: 1.1, fontWeight: FontWeight.w600, color: PxColors.muted),
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 8),
          ...children,
        ],
      ),
    );
  }
}

/// Değer göstergeli, çift tıklamayla sıfırlanan kaydırıcı.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.onChangeEnd,
    this.defaultValue = 0,
    this.suffix = '',
    this.decimals = 0,
    this.icon,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;
  final ValueChanged<double>? onChangeEnd;
  final double defaultValue;
  final String suffix;
  final int decimals;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final changed = (value - defaultValue).abs() > 0.0001;
    final shown = decimals == 0 ? value.round().toString() : value.toStringAsFixed(decimals).replaceAll('.', ',');
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              if (icon != null) ...[Icon(icon, size: 15, color: PxColors.muted), const SizedBox(width: 6)],
              Expanded(
                child: GestureDetector(
                  onDoubleTap: () {
                    onChanged(defaultValue);
                    onChangeEnd?.call(defaultValue);
                  },
                  child: Text(label, style: TextStyle(fontSize: 13, color: changed ? PxColors.text : PxColors.muted)),
                ),
              ),
              Text('$shown$suffix',
                  style: TextStyle(
                      fontSize: 12.5,
                      fontFeatures: const [FontFeature.tabularFigures()],
                      color: changed ? PxColors.accent : PxColors.muted)),
            ],
          ),
          SizedBox(
            height: 30,
            child: Slider(
              value: value.clamp(min, max).toDouble(),
              min: min,
              max: max,
              onChanged: onChanged,
              onChangeEnd: onChangeEnd,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renk seçici düğmesi (hazır palet + HEX).
class ColorButton extends StatelessWidget {
  const ColorButton({super.key, required this.color, required this.onChanged, this.label, this.allowTransparent = false});

  final int color;
  final ValueChanged<int> onChanged;
  final String? label;
  final bool allowTransparent;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () async {
        final picked = await showColorPicker(context, color, allowTransparent: allowTransparent);
        if (picked != null) onChanged(picked);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ColorSwatchBox(color: color),
            if (label != null) ...[const SizedBox(width: 8), Text(label!, style: const TextStyle(fontSize: 13))],
          ],
        ),
      ),
    );
  }
}

class ColorSwatchBox extends StatelessWidget {
  const ColorSwatchBox({super.key, required this.color, this.size = 26, this.selected = false});
  final int color;
  final double size;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: selected ? PxColors.accent : PxColors.border, width: selected ? 2 : 1),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(5),
        child: CustomPaint(painter: _SwatchPainter(Color(color))),
      ),
    );
  }
}

class _SwatchPainter extends CustomPainter {
  _SwatchPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.alpha < 255) {
      const cell = 5.0;
      final p1 = Paint()..color = const Color(0xFF3A3F4F);
      final p2 = Paint()..color = const Color(0xFF262A36);
      for (var y = 0.0; y < size.height; y += cell) {
        for (var x = 0.0; x < size.width; x += cell) {
          final even = ((x / cell).floor() + (y / cell).floor()).isEven;
          canvas.drawRect(Rect.fromLTWH(x, y, cell, cell), even ? p1 : p2);
        }
      }
    }
    canvas.drawRect(Offset.zero & size, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_SwatchPainter old) => old.color != color;
}

const List<int> kPalette = [
  0xFFFFFFFF, 0xFFE7E9F1, 0xFFA0A6B8, 0xFF5B6275, 0xFF2A2F3D, 0xFF000000, //
  0xFFFF5C7A, 0xFFFF8A3D, 0xFFFFC53D, 0xFFFFE680, 0xFF3DDC97, 0xFF14B8A6, //
  0xFF22D3EE, 0xFF3B82F6, 0xFF7C5CFF, 0xFFB15CFF, 0xFFFF5CD6, 0xFF8B5A2B, //
  0xFFF5E6CC, 0xFF1E3A5F, 0xFF0F5132, 0xFF7F1D1D, 0xFF4C1D95, 0xFF111827,
];

Future<int?> showColorPicker(BuildContext context, int initial, {bool allowTransparent = false}) {
  return showDialog<int>(
    context: context,
    builder: (context) => _ColorPickerDialog(initial: initial, allowTransparent: allowTransparent),
  );
}

class _ColorPickerDialog extends StatefulWidget {
  const _ColorPickerDialog({required this.initial, required this.allowTransparent});
  final int initial;
  final bool allowTransparent;

  @override
  State<_ColorPickerDialog> createState() => _ColorPickerDialogState();
}

class _ColorPickerDialogState extends State<_ColorPickerDialog> {
  late int _color = widget.initial;
  late final TextEditingController _hex = TextEditingController(text: _toHex(widget.initial));

  static String _toHex(int c) => (c & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase();

  void _set(int c, {bool updateText = true}) {
    setState(() => _color = c);
    if (updateText) _hex.text = _toHex(c);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alpha = (_color >> 24) & 255;
    return AlertDialog(
      title: const Text('Renk seç'),
      content: SizedBox(
        width: 320,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in kPalette)
                  GestureDetector(
                    onTap: () => _set((alpha << 24) | (c & 0xFFFFFF)),
                    child: ColorSwatchBox(color: c, size: 34, selected: (c & 0xFFFFFF) == (_color & 0xFFFFFF)),
                  ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                ColorSwatchBox(color: _color, size: 40),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _hex,
                    decoration: const InputDecoration(prefixText: '#', labelText: 'HEX'),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp('[0-9a-fA-F]')),
                      LengthLimitingTextInputFormatter(6),
                    ],
                    onChanged: (v) {
                      if (v.length == 6) {
                        final rgb = int.tryParse(v, radix: 16);
                        if (rgb != null) _set((alpha << 24) | rgb, updateText: false);
                      }
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            LabeledSlider(
              label: 'Opaklık',
              value: alpha / 255 * 100,
              min: widget.allowTransparent ? 0 : 5,
              max: 100,
              defaultValue: 100,
              suffix: '%',
              onChanged: (v) => _set(((v / 100 * 255).round() << 24) | (_color & 0xFFFFFF), updateText: false),
            ),
          ],
        ),
      ),
      actions: [
        if (widget.allowTransparent)
          TextButton(onPressed: () => Navigator.pop(context, 0), child: const Text('Yok (şeffaf)')),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(onPressed: () => Navigator.pop(context, _color), child: const Text('Seç')),
      ],
    );
  }
}

/// Basit onay penceresi.
Future<bool> confirm(BuildContext context,
    {required String title, required String message, String ok = 'Tamam', bool danger = false}) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('İptal')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: PxColors.danger) : null,
          onPressed: () => Navigator.pop(context, true),
          child: Text(ok),
        ),
      ],
    ),
  );
  return r ?? false;
}

Future<String?> promptText(BuildContext context, {required String title, String initial = '', String label = '', String ok = 'Kaydet'}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('İptal')),
        FilledButton(onPressed: () => Navigator.pop(context, controller.text), child: Text(ok)),
      ],
    ),
  ).whenComplete(controller.dispose);
}

void showMessage(BuildContext context, String message, {bool error = false}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(error ? Icons.error_outline : Icons.check_circle_outline, color: error ? PxColors.danger : PxColors.success, size: 20),
          const SizedBox(width: 10),
          Expanded(child: Text(message)),
        ],
      ),
      duration: Duration(seconds: error ? 6 : 3),
    ),
  );
}

/// Seçilebilir küçük "çip" düğme.
class PxChip extends StatelessWidget {
  const PxChip({super.key, required this.label, required this.selected, required this.onTap, this.icon});
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PxColors.primary.withOpacity(0.22) : PxColors.surface3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: selected ? PxColors.primary : PxColors.border),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[Icon(icon, size: 15), const SizedBox(width: 5)],
              Text(label, style: const TextStyle(fontSize: 12.5)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Bilgi kutusu (ör. format sınırlamaları, gizlilik notları).
class InfoBox extends StatelessWidget {
  const InfoBox({super.key, required this.text, this.icon = Icons.info_outline, this.color = PxColors.accent});
  final String text;
  final IconData icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 17, color: color),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: const TextStyle(fontSize: 12.5, height: 1.35))),
        ],
      ),
    );
  }
}

/// Yüklenme/işlem katmanı.
class BusyOverlay extends StatelessWidget {
  const BusyOverlay({super.key, required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: ColoredBox(
        color: const Color(0x99000000),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 18),
            decoration: BoxDecoration(
              color: PxColors.surface2,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: PxColors.border),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5)),
                const SizedBox(width: 14),
                Text(message),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
