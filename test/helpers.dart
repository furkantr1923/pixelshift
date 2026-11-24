import 'dart:io';
import 'dart:math' as math;

import 'package:pixelshift/image_engine/raster.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

export 'package:pixelshift/self_test.dart' show meanAbsDiff, syntheticImage;

bool _ffiReady = false;

void ensureFfi() {
  if (_ffiReady) return;
  sqfliteFfiInit();
  _ffiReady = true;
}

Future<Directory> tempDir(String prefix) => Directory.systemTemp.createTemp(prefix);

/// Rastgele gürültülü, alfa kanallı görüntü (kodlayıcı stres testi).
Raster noiseImage(int w, int h, {int seed = 1, bool alpha = true}) {
  final rnd = math.Random(seed);
  final r = Raster(w, h);
  for (var i = 0; i < r.rgba.length; i += 4) {
    r.rgba[i] = rnd.nextInt(256);
    r.rgba[i + 1] = rnd.nextInt(256);
    r.rgba[i + 2] = rnd.nextInt(256);
    r.rgba[i + 3] = alpha ? rnd.nextInt(256) : 255;
  }
  return r;
}
