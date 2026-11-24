import 'dart:ui';

/// Hazır kolaj düzeni: normalize (0..1) hücre dikdörtgenleri.
class CollageLayout {
  const CollageLayout(this.id, this.name, this.cells);
  final String id;
  final String name;
  final List<Rect> cells;

  static Rect _r(double l, double t, double r, double b) => Rect.fromLTRB(l, t, r, b);

  static final List<CollageLayout> all = [
    CollageLayout('2v', '2 — yan yana', [_r(0, 0, .5, 1), _r(.5, 0, 1, 1)]),
    CollageLayout('2h', '2 — alt alta', [_r(0, 0, 1, .5), _r(0, .5, 1, 1)]),
    CollageLayout('3a', '3 — büyük sol', [_r(0, 0, .6, 1), _r(.6, 0, 1, .5), _r(.6, .5, 1, 1)]),
    CollageLayout('3b', '3 — büyük üst', [_r(0, 0, 1, .6), _r(0, .6, .5, 1), _r(.5, .6, 1, 1)]),
    CollageLayout('3c', '3 — şeritler', [_r(0, 0, 1 / 3, 1), _r(1 / 3, 0, 2 / 3, 1), _r(2 / 3, 0, 1, 1)]),
    CollageLayout('4g', '4 — ızgara', [_r(0, 0, .5, .5), _r(.5, 0, 1, .5), _r(0, .5, .5, 1), _r(.5, .5, 1, 1)]),
    CollageLayout('4a', '4 — büyük üst', [_r(0, 0, 1, .62), _r(0, .62, 1 / 3, 1), _r(1 / 3, .62, 2 / 3, 1), _r(2 / 3, .62, 1, 1)]),
    CollageLayout('5a', '5 — mozaik', [_r(0, 0, .5, .6), _r(.5, 0, 1, .4), _r(.5, .4, 1, .8), _r(0, .6, .5, 1), _r(.5, .8, 1, 1)]),
    CollageLayout('6g', '6 — ızgara', [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 2; c++) _r(c / 2, r / 3, (c + 1) / 2, (r + 1) / 3),
    ]),
    CollageLayout('9g', '9 — ızgara', [
      for (var r = 0; r < 3; r++)
        for (var c = 0; c < 3; c++) _r(c / 3, r / 3, (c + 1) / 3, (r + 1) / 3),
    ]),
  ];

  /// Boşluk ve kenar payı uygulanmış piksel dikdörtgenleri.
  List<Rect> pixelCells(double width, double height, double spacing) {
    return [
      for (final c in cells)
        Rect.fromLTRB(
          c.left * width + (c.left == 0 ? spacing : spacing / 2),
          c.top * height + (c.top == 0 ? spacing : spacing / 2),
          c.right * width - (c.right >= 0.999 ? spacing : spacing / 2),
          c.bottom * height - (c.bottom >= 0.999 ? spacing : spacing / 2),
        ),
    ];
  }
}
