import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../app/theme.dart';
import '../../app/widgets.dart';
import '../../filters/filter_presets.dart';
import '../../image_engine/engine.dart';
import '../../platform_services/ui_images.dart';
import '../editor_controller.dart';

/// Hazır filtreler: küçük resimler GPU renk matrisiyle anında üretilir.
class FilterPanel extends StatefulWidget {
  const FilterPanel({super.key, required this.controller, this.horizontal = false});
  final EditorController controller;
  final bool horizontal;

  @override
  State<FilterPanel> createState() => _FilterPanelState();
}

class _FilterPanelState extends State<FilterPanel> {
  ui.Image? _thumb;

  @override
  void initState() {
    super.initState();
    _makeThumb();
  }

  Future<void> _makeThumb() async {
    final src = widget.controller.sourcePreview;
    if (src == null) return;
    final small = await ImageEngine.thumbnail(src, 160);
    final img = await UiImages.fromRaster(small);
    if (!mounted) {
      img.dispose();
      return;
    }
    setState(() => _thumb = img);
  }

  @override
  void dispose() {
    _thumb?.dispose();
    super.dispose();
  }

  Widget _tile(FilterPreset f, bool selected) {
    final c = widget.controller;
    final a = c.doc.adjustments;
    final matrix = a.copyWith(filterId: f.id, filterIntensity: 100).colorMatrix().values;
    return GestureDetector(
      onTap: () => c.commitAdjustments('Filtre: ${f.name}', a.copyWith(filterId: f.id, filterIntensity: f.id == 'none' ? 100 : a.filterIntensity == 0 ? 100 : a.filterIntensity)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: selected ? PxColors.accent : PxColors.border, width: selected ? 2 : 1),
            ),
            clipBehavior: Clip.antiAlias,
            child: _thumb == null
                ? const ColoredBox(color: PxColors.surface3)
                : ColorFiltered(
                    colorFilter: ColorFilter.matrix(matrix),
                    child: RawImage(image: _thumb, fit: BoxFit.cover),
                  ),
          ),
          const SizedBox(height: 4),
          Text(f.name,
              style: TextStyle(fontSize: 11.5, color: selected ? PxColors.text : PxColors.muted),
              overflow: TextOverflow.ellipsis),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.controller;
    return ListenableBuilder(
      listenable: c,
      builder: (context, _) {
        final a = c.doc.adjustments;
        final intensity = a.filterId == 'none'
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.fromLTRB(14, 4, 14, 0),
                child: LabeledSlider(
                  label: 'Yoğunluk (${a.filter.name})',
                  value: a.filterIntensity,
                  min: 0,
                  max: 100,
                  defaultValue: 100,
                  suffix: '%',
                  onChanged: (v) => c.previewAdjustments(a.copyWith(filterIntensity: v)),
                  onChangeEnd: (v) => c.commitAdjustments('Filtre yoğunluğu', a.copyWith(filterIntensity: v)),
                ),
              );
        final tiles = [for (final f in FilterPresets.all) _tile(f, f.id == a.filterId)];
        if (widget.horizontal) {
          return Column(
            children: [
              intensity,
              SizedBox(
                height: 104,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  itemCount: tiles.length,
                  separatorBuilder: (_, __) => const SizedBox(width: 10),
                  itemBuilder: (_, i) => tiles[i],
                ),
              ),
            ],
          );
        }
        return ListView(
          children: [
            intensity,
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(spacing: 10, runSpacing: 12, children: tiles),
            ),
          ],
        );
      },
    );
  }
}
