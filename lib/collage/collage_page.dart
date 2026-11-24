import 'package:flutter/material.dart';

import '../app/services.dart';
import '../app/theme.dart';
import '../app/widgets.dart';
import '../core/errors.dart';
import '../projects/project_factory.dart';
import 'collage_layouts.dart';

/// Kolaj oluşturucu: düzen, tuval, boşluk ve fotoğraflar.
class CollagePage extends StatefulWidget {
  const CollagePage({super.key});

  @override
  State<CollagePage> createState() => _CollagePageState();
}

class _CollagePageState extends State<CollagePage> {
  CollageLayout _layout = CollageLayout.all[5];
  (String, int, int) _size = _sizes.first;
  double _spacing = 24;
  double _radius = 18;
  int _background = 0xFFFFFFFF;
  bool _busy = false;
  String _status = '';

  static const _sizes = [
    ('Kare', 2048, 2048),
    ('Dikey 4:5', 1638, 2048),
    ('Yatay 3:2', 2400, 1600),
    ('Hikâye 9:16', 1080, 1920),
  ];

  Future<void> _create() async {
    final services = Services.of(context);
    try {
      final photos = services.files.isAndroid
          ? await services.files.pickFromGallery(multiple: true)
          : await services.files.pickFiles(multiple: true);
      if (photos.isEmpty || !mounted) return;
      setState(() {
        _busy = true;
        _status = 'Fotoğraflar hazırlanıyor…';
      });
      final scale = _size.$2 / 2048;
      final created = await ProjectFactory(services).collage(
        layout: _layout,
        width: _size.$2,
        height: _size.$3,
        spacing: _spacing * scale,
        radius: _radius * scale,
        background: _background,
        photos: photos,
        progress: (d, t) {
          if (mounted) setState(() => _status = 'Fotoğraf ${d + 1 > t ? t : d + 1} / $t işleniyor…');
        },
      );
      if (mounted) Navigator.pop(context, created);
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        showMessage(context, describeError(e), error: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 900;
    final preview = AspectRatio(
      aspectRatio: _size.$2 / _size.$3,
      child: LayoutBuilder(builder: (context, c) {
        final s = c.maxWidth / _size.$2;
        final cells = _layout.pixelCells(_size.$2.toDouble(), _size.$3.toDouble(), _spacing * _size.$2 / 2048);
        return Container(
          color: Color(_background),
          child: Stack(
            children: [
              for (var i = 0; i < cells.length; i++)
                Positioned(
                  left: cells[i].left * s,
                  top: cells[i].top * s,
                  width: cells[i].width * s,
                  height: cells[i].height * s,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: [
                        PxColors.primary.withOpacity(0.55),
                        PxColors.accent.withOpacity(0.55),
                      ], begin: Alignment.topLeft, end: Alignment.bottomRight),
                      borderRadius: BorderRadius.circular(_radius * _size.$2 / 2048 * s),
                    ),
                    alignment: Alignment.center,
                    child: Text('${i + 1}', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
                  ),
                ),
            ],
          ),
        );
      }),
    );
    final options = ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Düzen', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final l in CollageLayout.all)
              GestureDetector(
                onTap: () => setState(() => _layout = l),
                child: Container(
                  width: 64,
                  height: 64,
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: PxColors.surface3,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: l == _layout ? PxColors.accent : PxColors.border, width: l == _layout ? 2 : 1),
                  ),
                  child: CustomPaint(painter: _LayoutIcon(l)),
                ),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(_layout.name, style: const TextStyle(color: PxColors.muted, fontSize: 12)),
        const SizedBox(height: 16),
        const Text('Tuval', style: TextStyle(fontWeight: FontWeight.w600)),
        const SizedBox(height: 8),
        Wrap(spacing: 6, runSpacing: 6, children: [
          for (final s in _sizes) PxChip(label: '${s.$1} (${s.$2}×${s.$3})', selected: s == _size, onTap: () => setState(() => _size = s)),
        ]),
        const SizedBox(height: 12),
        LabeledSlider(label: 'Boşluk', value: _spacing, min: 0, max: 80, defaultValue: 24, onChanged: (v) => setState(() => _spacing = v)),
        LabeledSlider(label: 'Köşe yuvarlama', value: _radius, min: 0, max: 120, defaultValue: 18, onChanged: (v) => setState(() => _radius = v)),
        ColorButton(color: _background, label: 'Arka plan rengi', onChanged: (v) => setState(() => _background = v)),
        const SizedBox(height: 16),
        const InfoBox(text: 'Fotoğrafları seçtikten sonra düzenleyicide her birini taşıyabilir, boyutlandırabilir, döndürebilir, '
            'çerçeve ekleyebilir ve kutu içinde kaydırabilirsiniz.'),
        const SizedBox(height: 16),
        FilledButton.icon(
          onPressed: _busy ? null : _create,
          icon: const Icon(Icons.add_photo_alternate_outlined),
          label: Text('Fotoğrafları seç (en fazla ${_layout.cells.length})'),
        ),
      ],
    );
    return Scaffold(
      appBar: AppBar(title: const Text('Kolaj oluştur')),
      body: Stack(
        children: [
          wide
              ? Row(children: [
                  Expanded(child: Center(child: Padding(padding: const EdgeInsets.all(32), child: preview))),
                  SizedBox(width: 380, child: options),
                ])
              : Column(children: [
                  Padding(padding: const EdgeInsets.all(16), child: SizedBox(height: 260, child: Center(child: preview))),
                  Expanded(child: options),
                ]),
          if (_busy) BusyOverlay(message: _status),
        ],
      ),
    );
  }
}

class _LayoutIcon extends CustomPainter {
  _LayoutIcon(this.layout);
  final CollageLayout layout;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()..color = PxColors.muted;
    for (final c in layout.pixelCells(size.width, size.height, 2)) {
      canvas.drawRRect(RRect.fromRectAndRadius(c, const Radius.circular(2)), p);
    }
  }

  @override
  bool shouldRepaint(_LayoutIcon old) => old.layout != layout;
}
