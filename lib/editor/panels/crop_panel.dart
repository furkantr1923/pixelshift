import 'package:flutter/material.dart';

import '../../app/widgets.dart';
import '../editor_controller.dart';

/// Kırpma, döndürme, çevirme ve düzleştirme.
class CropPanel extends StatelessWidget {
  const CropPanel({super.key, required this.controller, this.compact = false});
  final EditorController controller;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final g = controller.doc.geometry;
        final aspects = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final a in CropAspect.presets)
              PxChip(label: a.label, selected: controller.cropAspect == a, onTap: () => controller.setCropAspect(a)),
          ],
        );
        final transforms = Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _iconBtn(Icons.rotate_left, 'Sola döndür', () => controller.rotate90(clockwise: false)),
            _iconBtn(Icons.rotate_right, 'Sağa döndür', () => controller.rotate90()),
            _iconBtn(Icons.flip, 'Yatay çevir', () => controller.flip(horizontal: true)),
            _iconBtn(Icons.flip, 'Dikey çevir', () => controller.flip(horizontal: false), quarter: true),
            _iconBtn(Icons.restart_alt, 'Sıfırla', controller.resetGeometry),
          ],
        );
        final straighten = LabeledSlider(
          label: 'Düzleştir',
          value: g.straighten,
          min: -45,
          max: 45,
          decimals: 1,
          suffix: '°',
          icon: Icons.straighten,
          onChanged: controller.previewStraighten,
          onChangeEnd: (_) => controller.commitStraighten(),
        );
        final actions = Row(
          children: [
            Expanded(
              child: OutlinedButton(onPressed: () => controller.cancelCrop(), child: const Text('İptal')),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.icon(
                onPressed: controller.applyCrop,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Uygula'),
              ),
            ),
          ],
        );
        if (compact) {
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            children: [
              SingleChildScrollView(scrollDirection: Axis.horizontal, child: Row(children: [
                for (final a in CropAspect.presets)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: PxChip(label: a.label, selected: controller.cropAspect == a, onTap: () => controller.setCropAspect(a)),
                  ),
              ])),
              const SizedBox(height: 8),
              transforms,
              straighten,
              actions,
            ],
          );
        }
        return ListView(
          children: [
            PanelSection(title: 'Oran', children: [aspects]),
            PanelSection(title: 'Döndür ve çevir', children: [transforms, const SizedBox(height: 10), straighten]),
            Padding(padding: const EdgeInsets.fromLTRB(14, 8, 14, 14), child: actions),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 14),
              child: InfoBox(text: 'Köşe ve kenarları sürükleyerek kırpın; dikdörtgenin içini sürükleyerek taşıyın. '
                  'Kırpma tahribatsızdır, istediğiniz zaman geri alabilirsiniz.'),
            ),
          ],
        );
      },
    );
  }

  Widget _iconBtn(IconData icon, String tooltip, VoidCallback onTap, {bool quarter = false}) {
    return Tooltip(
      message: tooltip,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(10), minimumSize: const Size(44, 44)),
        onPressed: onTap,
        child: quarter ? RotatedBox(quarterTurns: 1, child: Icon(icon, size: 20)) : Icon(icon, size: 20),
      ),
    );
  }
}
