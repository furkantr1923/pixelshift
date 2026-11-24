import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../app/theme.dart';
import '../layers/layer.dart';
import '../layers/layer_painter.dart';
import 'templates.dart';

/// Şablon galerisi: önizlemeler aynı katman çizicisiyle canlı üretilir.
class TemplatesPage extends StatefulWidget {
  const TemplatesPage({super.key});

  @override
  State<TemplatesPage> createState() => _TemplatesPageState();
}

class _TemplatesPageState extends State<TemplatesPage> {
  String _category = 'Tümü';
  late final Map<String, List<Layer>> _previewLayers = {
    for (final t in DesignTemplate.all) t.id: t.build(t.width.toDouble(), t.height.toDouble()),
  };

  @override
  Widget build(BuildContext context) {
    final categories = ['Tümü', ...{for (final t in DesignTemplate.all) t.category}];
    final items = DesignTemplate.all.where((t) => _category == 'Tümü' || t.category == _category).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Şablonlar')),
      body: Column(
        children: [
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                for (final c in categories)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: ChoiceChip(label: Text(c), selected: c == _category, onSelected: (_) => setState(() => _category = c)),
                  ),
              ],
            ),
          ),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 260,
                mainAxisSpacing: 16,
                crossAxisSpacing: 16,
                childAspectRatio: 0.78,
              ),
              itemCount: items.length,
              itemBuilder: (context, i) {
                final t = items[i];
                return Material(
                  color: PxColors.surface2,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: PxColors.border)),
                  child: InkWell(
                    onTap: () => Navigator.pop(context, t),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Center(
                              child: AspectRatio(
                                aspectRatio: t.width / t.height,
                                child: CustomPaint(painter: _TemplatePreview(t, _previewLayers[t.id]!)),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(t.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                              Text('${t.category} • ${t.width}×${t.height}', style: const TextStyle(fontSize: 11.5, color: PxColors.muted)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _TemplatePreview extends CustomPainter {
  _TemplatePreview(this.t, this.layers);
  final DesignTemplate t;
  final List<Layer> layers;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / t.width;
    canvas.clipRect(Offset.zero & size);
    canvas.scale(s);
    final r = Rect.fromLTWH(0, 0, t.width.toDouble(), t.height.toDouble());
    canvas.drawRect(r, Paint()..shader = ui.Gradient.linear(r.topCenter, r.bottomCenter, [Color(t.top), Color(t.bottom)]));
    LayerPainter.paintLayers(canvas, layers, const {});
  }

  @override
  bool shouldRepaint(_TemplatePreview old) => old.t != t;
}
