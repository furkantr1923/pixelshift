import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../filters/adjustments.dart';
import '../editor_controller.dart';

/// Işık, renk, detay ve efekt ayarları.
class AdjustPanel extends StatelessWidget {
  const AdjustPanel({super.key, required this.controller});
  final EditorController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final a = controller.doc.adjustments;
        Widget slider(String label, double value, Adjustments Function(double v) apply,
            {double min = -100, double max = 100, IconData? icon}) {
          return LabeledSlider(
            label: label,
            value: value,
            min: min,
            max: max,
            icon: icon,
            onChanged: (v) => controller.previewAdjustments(apply(v)),
            onChangeEnd: (v) => controller.commitAdjustments(label, apply(v)),
          );
        }

        return ListView(
          padding: const EdgeInsets.only(bottom: 16),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: controller.autoAdjust,
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: const Text('Otomatik'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: a.isNeutral ? null : controller.resetAdjustments,
                    icon: const Icon(Icons.restart_alt, size: 18),
                    label: const Text('Sıfırla'),
                  ),
                ],
              ),
            ),
            PanelSection(title: 'Işık', children: [
              slider('Pozlama', a.exposure, (v) => a.copyWith(exposure: v), icon: Icons.exposure),
              slider('Parlaklık', a.brightness, (v) => a.copyWith(brightness: v), icon: Icons.brightness_6_outlined),
              slider('Kontrast', a.contrast, (v) => a.copyWith(contrast: v), icon: Icons.contrast),
              slider('Gölgeler', a.shadows, (v) => a.copyWith(shadows: v), icon: Icons.brightness_low),
              slider('Açık tonlar', a.highlights, (v) => a.copyWith(highlights: v), icon: Icons.brightness_high),
            ]),
            PanelSection(title: 'Renk', children: [
              slider('Doygunluk', a.saturation, (v) => a.copyWith(saturation: v), icon: Icons.palette_outlined),
              slider('Sıcaklık', a.temperature, (v) => a.copyWith(temperature: v), icon: Icons.thermostat),
              slider('Ton', a.tint, (v) => a.copyWith(tint: v), icon: Icons.gradient),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Gri tonlama', style: TextStyle(fontSize: 13)),
                value: a.grayscale,
                onChanged: (v) => controller.commitAdjustments('Gri tonlama', a.copyWith(grayscale: v)),
              ),
            ]),
            PanelSection(title: 'Detay', children: [
              slider('Keskinlik', a.sharpness, (v) => a.copyWith(sharpness: v), min: 0, icon: Icons.details),
              slider('Netlik', a.clarity, (v) => a.copyWith(clarity: v), min: 0, icon: Icons.blur_linear),
              slider('Bulanıklık', a.blur, (v) => a.copyWith(blur: v), min: 0, icon: Icons.blur_on),
            ]),
            PanelSection(title: 'Efektler', children: [
              slider('Vinyet', a.vignette, (v) => a.copyWith(vignette: v), icon: Icons.vignette_outlined),
              slider('Gren', a.grain, (v) => a.copyWith(grain: v), min: 0, icon: Icons.grain),
            ]),
            const Padding(
              padding: EdgeInsets.fromLTRB(14, 4, 14, 0),
              child: Text('İpucu: Bir ayarın adına çift tıklayarak sıfırlayabilirsiniz.',
                  style: TextStyle(fontSize: 11.5, color: PxColors.muted)),
            ),
          ],
        );
      },
    );
  }
}
