import 'dart:math' as math;
import 'dart:typed_data';

import 'geometry.dart';
import 'raster.dart';

/// Saf Dart görüntü işlemleri. Tümü isolate içinde çalışacak şekilde
/// yan etkisiz yazılmıştır (girdi değiştirilmez, yeni [Raster] döner)
/// — "yerinde" olanlar adında belirtilir.
class Ops {
  Ops._();

  // ------------------------------------------------------------ Geometri

  /// 90° döndürme (saat yönünde) ve çevirme.
  static Raster orient(Raster src, int quarterTurns, {bool flipH = false, bool flipV = false}) {
    final q = quarterTurns % 4;
    if (q == 0 && !flipH && !flipV) return src;
    final w = src.width, h = src.height;
    final ow = q.isOdd ? h : w;
    final oh = q.isOdd ? w : h;
    final out = Raster(ow, oh);
    final s = Uint32List.view(src.rgba.buffer, src.rgba.offsetInBytes, w * h);
    final d = Uint32List.view(out.rgba.buffer, out.rgba.offsetInBytes, ow * oh);
    for (var oy = 0; oy < oh; oy++) {
      for (var ox = 0; ox < ow; ox++) {
        // Önce çevirme çıktı koordinatlarında uygulanır.
        final fx = flipH ? ow - 1 - ox : ox;
        final fy = flipV ? oh - 1 - oy : oy;
        int sx, sy;
        switch (q) {
          case 1: // saat yönünde 90: çıktı (x,y) <- kaynak (y, h-1-x)
            sx = fy;
            sy = h - 1 - fx;
          case 2:
            sx = w - 1 - fx;
            sy = h - 1 - fy;
          case 3:
            sx = w - 1 - fy;
            sy = fx;
          default:
            sx = fx;
            sy = fy;
        }
        d[oy * ow + ox] = s[sy * w + sx];
      }
    }
    return out;
  }

  /// Serbest açıyla düzleştirme + aynı en-boy oranında en büyük iç kırpma.
  /// Pozitif açı içeriği saat yönünde döndürür. Çift doğrusal örnekleme.
  static Raster straighten(Raster src, double degrees) {
    if (degrees == 0) return src;
    final (ow, oh) = Geometry.straightenedSize(src.width, src.height, degrees);
    final out = Raster(ow, oh);
    final a = degrees * math.pi / 180;
    final c = math.cos(a), s = math.sin(a);
    final scx = (src.width - 1) / 2, scy = (src.height - 1) / 2;
    final ocx = (ow - 1) / 2, ocy = (oh - 1) / 2;
    final d = out.rgba;
    var di = 0;
    for (var y = 0; y < oh; y++) {
      final dy = y - ocy;
      for (var x = 0; x < ow; x++) {
        final dx = x - ocx;
        // Ters dönüşüm: çıktı noktasını kaynağa geri döndür.
        final sx = dx * c + dy * s + scx;
        final sy = -dx * s + dy * c + scy;
        _sampleBilinear(src, sx, sy, d, di);
        di += 4;
      }
    }
    return out;
  }

  static void _sampleBilinear(Raster src, double x, double y, Uint8List out, int oi) {
    final w = src.width, h = src.height;
    if (x < 0) x = 0;
    if (y < 0) y = 0;
    if (x > w - 1) x = (w - 1).toDouble();
    if (y > h - 1) y = (h - 1).toDouble();
    final x0 = x.floor(), y0 = y.floor();
    final x1 = x0 + 1 < w ? x0 + 1 : x0;
    final y1 = y0 + 1 < h ? y0 + 1 : y0;
    final fx = x - x0, fy = y - y0;
    final p = src.rgba;
    final i00 = (y0 * w + x0) * 4, i10 = (y0 * w + x1) * 4;
    final i01 = (y1 * w + x0) * 4, i11 = (y1 * w + x1) * 4;
    for (var k = 0; k < 4; k++) {
      final top = p[i00 + k] + (p[i10 + k] - p[i00 + k]) * fx;
      final bot = p[i01 + k] + (p[i11 + k] - p[i01 + k]) * fx;
      out[oi + k] = clamp255(top + (bot - top) * fy);
    }
  }

  static Raster crop(Raster src, NormRect rect) {
    if (rect.isFull) return src;
    final r = rect.clampValid();
    final x = (r.left * src.width).round().clamp(0, src.width - 1);
    final y = (r.top * src.height).round().clamp(0, src.height - 1);
    final w = math.max(1, (r.width * src.width).round()).clamp(1, src.width - x);
    final h = math.max(1, (r.height * src.height).round()).clamp(1, src.height - y);
    return cropPixels(src, IntRect(x, y, w, h));
  }

  static Raster cropPixels(Raster src, IntRect r) {
    final out = Raster(r.width, r.height);
    final rowBytes = r.width * 4;
    for (var row = 0; row < r.height; row++) {
      final si = ((r.y + row) * src.width + r.x) * 4;
      out.rgba.setRange(row * rowBytes, row * rowBytes + rowBytes, src.rgba, si);
    }
    return out;
  }

  static Raster applyGeometry(Raster src, Geometry g) {
    var r = orient(src, g.quarterTurns, flipH: g.flipH, flipV: g.flipV);
    r = straighten(r, g.straighten);
    r = crop(r, g.crop);
    return r;
  }

  // ------------------------------------------------------------ Boyutlandırma

  /// Kaliteli yeniden boyutlandırma: küçültmede alan ortalaması,
  /// büyütmede bikübik (Catmull-Rom).
  static Raster resize(Raster src, int width, int height) {
    if (width == src.width && height == src.height) return src;
    if (width <= src.width && height <= src.height) return _resizeArea(src, width, height);
    return _resizeBicubic(src, width, height);
  }

  /// Uzun kenarı en fazla [maxSide] olacak şekilde küçültür.
  static Raster fitWithin(Raster src, int maxSide) {
    if (src.longSide <= maxSide) return src;
    final scale = maxSide / src.longSide;
    return resize(src, math.max(1, (src.width * scale).round()), math.max(1, (src.height * scale).round()));
  }

  static Raster _resizeArea(Raster src, int ow, int oh) {
    final out = Raster(ow, oh);
    final sw = src.width, sh = src.height;
    final sx = sw / ow, sy = sh / oh;
    final p = src.rgba;
    final d = out.rgba;
    // Önce yatay, sonra dikey geçiş (ayrılabilir kutu filtresi, kesirli kenarlar).
    final tmp = Float32List(ow * sh * 4);
    for (var y = 0; y < sh; y++) {
      for (var x = 0; x < ow; x++) {
        final x0 = x * sx, x1 = x0 + sx;
        var acc0 = 0.0, acc1 = 0.0, acc2 = 0.0, acc3 = 0.0;
        var ix = x0.floor();
        while (ix < x1 && ix < sw) {
          final left = math.max(x0, ix.toDouble());
          final right = math.min(x1, ix + 1.0);
          final wgt = right - left;
          if (wgt > 0) {
            final i = (y * sw + ix) * 4;
            final a = p[i + 3] * wgt;
            // Alfa ağırlıklı ortalama (şeffaf kenarlarda renk taşmasını önler).
            acc0 += p[i] * a;
            acc1 += p[i + 1] * a;
            acc2 += p[i + 2] * a;
            acc3 += a;
          }
          ix++;
        }
        final ti = (y * ow + x) * 4;
        tmp[ti] = acc0;
        tmp[ti + 1] = acc1;
        tmp[ti + 2] = acc2;
        tmp[ti + 3] = acc3;
      }
    }
    for (var y = 0; y < oh; y++) {
      final y0 = y * sy, y1 = y0 + sy;
      for (var x = 0; x < ow; x++) {
        var acc0 = 0.0, acc1 = 0.0, acc2 = 0.0, acc3 = 0.0;
        var iy = y0.floor();
        while (iy < y1 && iy < sh) {
          final top = math.max(y0, iy.toDouble());
          final bottom = math.min(y1, iy + 1.0);
          final wgt = bottom - top;
          if (wgt > 0) {
            final ti = (iy * ow + x) * 4;
            acc0 += tmp[ti] * wgt;
            acc1 += tmp[ti + 1] * wgt;
            acc2 += tmp[ti + 2] * wgt;
            acc3 += tmp[ti + 3] * wgt;
          }
          iy++;
        }
        final di = (y * ow + x) * 4;
        if (acc3 > 0) {
          d[di] = clamp255(acc0 / acc3);
          d[di + 1] = clamp255(acc1 / acc3);
          d[di + 2] = clamp255(acc2 / acc3);
          d[di + 3] = clamp255(acc3 / (sx * sy));
        }
      }
    }
    return out;
  }

  static double _cubic(double x) {
    // Catmull-Rom (a = -0.5)
    x = x.abs();
    if (x < 1) return 1.5 * x * x * x - 2.5 * x * x + 1;
    if (x < 2) return -0.5 * x * x * x + 2.5 * x * x - 4 * x + 2;
    return 0;
  }

  static Raster _resizeBicubic(Raster src, int ow, int oh) {
    final out = Raster(ow, oh);
    final sw = src.width, sh = src.height;
    final p = src.rgba;
    final d = out.rgba;
    final scaleX = sw / ow, scaleY = sh / oh;
    // Yatay ağırlıkları önceden hesapla.
    final xIdx = Int32List(ow * 4);
    final xW = Float64List(ow * 4);
    for (var x = 0; x < ow; x++) {
      final fx = (x + 0.5) * scaleX - 0.5;
      final ix = fx.floor();
      final t = fx - ix;
      for (var k = 0; k < 4; k++) {
        xIdx[x * 4 + k] = (ix - 1 + k).clamp(0, sw - 1);
        xW[x * 4 + k] = _cubic(t - (k - 1));
      }
    }
    for (var y = 0; y < oh; y++) {
      final fy = (y + 0.5) * scaleY - 0.5;
      final iy = fy.floor();
      final ty = fy - iy;
      final rows = [for (var k = 0; k < 4; k++) (iy - 1 + k).clamp(0, sh - 1)];
      final wy = [for (var k = 0; k < 4; k++) _cubic(ty - (k - 1))];
      for (var x = 0; x < ow; x++) {
        var r = 0.0, g = 0.0, b = 0.0, a = 0.0;
        for (var ky = 0; ky < 4; ky++) {
          final rowBase = rows[ky] * sw;
          final wyk = wy[ky];
          for (var kx = 0; kx < 4; kx++) {
            final wgt = wyk * xW[x * 4 + kx];
            final i = (rowBase + xIdx[x * 4 + kx]) * 4;
            r += p[i] * wgt;
            g += p[i + 1] * wgt;
            b += p[i + 2] * wgt;
            a += p[i + 3] * wgt;
          }
        }
        final di = (y * ow + x) * 4;
        d[di] = clamp255(r);
        d[di + 1] = clamp255(g);
        d[di + 2] = clamp255(b);
        d[di + 3] = clamp255(a);
      }
    }
    return out;
  }

  // ------------------------------------------------------------ Bulanıklık / detay

  /// Ayrılabilir kutu bulanıklığı; [passes]=3 Gauss'a yakın sonuç verir.
  static Raster boxBlur(Raster src, int radius, {int passes = 3}) {
    if (radius < 1) return src.clone();
    var cur = src.clone();
    final tmp = Uint8List(src.rgba.length);
    for (var p = 0; p < passes; p++) {
      _boxBlurH(cur.rgba, tmp, src.width, src.height, radius);
      _boxBlurV(tmp, cur.rgba, src.width, src.height, radius);
    }
    return cur;
  }

  static void _boxBlurH(Uint8List s, Uint8List d, int w, int h, int r) {
    final div = 2 * r + 1;
    for (var y = 0; y < h; y++) {
      final row = y * w;
      for (var c = 0; c < 4; c++) {
        var acc = 0;
        for (var k = -r; k <= r; k++) {
          acc += s[(row + k.clamp(0, w - 1)) * 4 + c];
        }
        for (var x = 0; x < w; x++) {
          d[(row + x) * 4 + c] = (acc / div).round();
          final outX = (x - r).clamp(0, w - 1);
          final inX = (x + r + 1).clamp(0, w - 1);
          acc += s[(row + inX) * 4 + c] - s[(row + outX) * 4 + c];
        }
      }
    }
  }

  static void _boxBlurV(Uint8List s, Uint8List d, int w, int h, int r) {
    final div = 2 * r + 1;
    for (var x = 0; x < w; x++) {
      for (var c = 0; c < 4; c++) {
        var acc = 0;
        for (var k = -r; k <= r; k++) {
          acc += s[(k.clamp(0, h - 1) * w + x) * 4 + c];
        }
        for (var y = 0; y < h; y++) {
          d[(y * w + x) * 4 + c] = (acc / div).round();
          final outY = (y - r).clamp(0, h - 1);
          final inY = (y + r + 1).clamp(0, h - 1);
          acc += s[(inY * w + x) * 4 + c] - s[(outY * w + x) * 4 + c];
        }
      }
    }
  }

  /// Keskinleştirme maskesi: orijinal + miktar * (orijinal - bulanık).
  static Raster unsharp(Raster src, {required int radius, required double amount, int threshold = 0}) {
    if (amount == 0) return src;
    final blurred = boxBlur(src, radius, passes: 2);
    final out = Raster(src.width, src.height);
    final s = src.rgba, b = blurred.rgba, d = out.rgba;
    for (var i = 0; i < s.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        final diff = s[i + c] - b[i + c];
        d[i + c] = diff.abs() < threshold ? s[i + c] : clamp255(s[i + c] + diff * amount);
      }
      d[i + 3] = s[i + 3];
    }
    return out;
  }

  /// Görüntü boyutuna oranlı yarıçap: önizleme ve tam çözünürlükte
  /// benzer görsel etki için.
  static int scaledRadius(Raster r, double basePer1000) =>
      math.max(1, (r.longSide / 1000 * basePer1000).round());

  // ------------------------------------------------------------ Ton

  /// Gölgeleri açar/koyulaştırır ve açık tonları geri kazanır.
  /// Renk tonunu korumak için parlaklık oranıyla ölçekler. (yerinde)
  static void shadowsHighlightsInPlace(Raster r, double shadows, double highlights) {
    if (shadows == 0 && highlights == 0) return;
    final sh = shadows / 100, hi = highlights / 100;
    // Parlaklık için LUT (0..255 -> çarpan).
    final lut = Float64List(256);
    for (var v = 0; v < 256; v++) {
      final l = v / 255;
      final ls = (1 - l) * (1 - l);
      final lh = l * l;
      final lc = l < 0.04 ? 0.04 : l;
      final nl = clamp01(l + sh * 0.45 * ls * lc * 2.2 + hi * 0.38 * lh * (1 - l * 0.35));
      lut[v] = l < 0.004 ? (sh > 0 ? 1 + sh * 0.5 : 1) : nl / l;
    }
    final d = r.rgba;
    for (var i = 0; i < d.length; i += 4) {
      final lum = (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]).round().clamp(0, 255);
      final k = lut[lum];
      d[i] = clamp255(d[i] * k);
      d[i + 1] = clamp255(d[i + 1] * k);
      d[i + 2] = clamp255(d[i + 2] * k);
    }
  }

  /// Vinyet: negatif değer kenarları karartır, pozitif aydınlatır. (yerinde)
  static void vignetteInPlace(Raster r, double amount) {
    if (amount == 0) return;
    final a = amount / 100;
    final w = r.width, h = r.height;
    final cx = (w - 1) / 2, cy = (h - 1) / 2;
    final maxD = math.sqrt(cx * cx + cy * cy);
    final d = r.rgba;
    for (var y = 0; y < h; y++) {
      final dy = (y - cy) / maxD;
      for (var x = 0; x < w; x++) {
        final dx = (x - cx) / maxD;
        final dist = math.sqrt(dx * dx + dy * dy);
        // 0.45'ten sonra yumuşak geçiş
        var t = clamp01((dist - 0.45) / 0.55);
        t = t * t * (3 - 2 * t);
        if (t == 0) continue;
        final i = (y * w + x) * 4;
        if (a < 0) {
          final k = 1 + a * t * 0.85;
          d[i] = clamp255(d[i] * k);
          d[i + 1] = clamp255(d[i + 1] * k);
          d[i + 2] = clamp255(d[i + 2] * k);
        } else {
          final k = a * t * 0.85;
          d[i] = clamp255(d[i] + (255 - d[i]) * k);
          d[i + 1] = clamp255(d[i + 1] + (255 - d[i + 1]) * k);
          d[i + 2] = clamp255(d[i + 2] + (255 - d[i + 2]) * k);
        }
      }
    }
  }

  /// Film grenlenmesi. Tohum sabittir: aynı görüntü her seferinde aynı sonucu verir. (yerinde)
  static void grainInPlace(Raster r, double amount, {int seed = 1337}) {
    if (amount <= 0) return;
    final rnd = math.Random(seed);
    final strength = amount / 100 * 38;
    final d = r.rgba;
    for (var i = 0; i < d.length; i += 4) {
      final n = (rnd.nextDouble() + rnd.nextDouble() - 1) * strength;
      d[i] = clamp255(d[i] + n);
      d[i + 1] = clamp255(d[i + 1] + n);
      d[i + 2] = clamp255(d[i + 2] + n);
    }
  }

  // ------------------------------------------------------------ Alfa / birleştirme

  /// Şeffaf pikselleri verilen renkle birleştirir (JPG/BMP için). (yerinde)
  static void flattenInPlace(Raster r, {int bgR = 255, int bgG = 255, int bgB = 255}) {
    final d = r.rgba;
    for (var i = 0; i < d.length; i += 4) {
      final a = d[i + 3];
      if (a == 255) continue;
      final t = a / 255;
      d[i] = clamp255(d[i] * t + bgR * (1 - t));
      d[i + 1] = clamp255(d[i + 1] * t + bgG * (1 - t));
      d[i + 2] = clamp255(d[i + 2] * t + bgB * (1 - t));
      d[i + 3] = 255;
    }
  }

  /// [top] görüntüsünü [bottom] üzerine (aynı boyut) normal karışımla birleştirir.
  static Raster compositeOver(Raster top, Raster bottom) {
    final out = bottom.clone();
    final t = top.rgba, d = out.rgba;
    for (var i = 0; i < d.length; i += 4) {
      final ta = t[i + 3] / 255;
      if (ta == 0) continue;
      final ba = d[i + 3] / 255;
      final oa = ta + ba * (1 - ta);
      for (var c = 0; c < 3; c++) {
        d[i + c] = clamp255((t[i + c] * ta + d[i + c] * ba * (1 - ta)) / oa);
      }
      d[i + 3] = clamp255(oa * 255);
    }
    return out;
  }

  /// Görüntüyü hedef kutuyu tamamen dolduracak şekilde (cover) ölçekleyip kırpar.
  static Raster cover(Raster src, int width, int height) {
    final scale = math.max(width / src.width, height / src.height);
    final sw = math.max(width, (src.width * scale).round());
    final sh = math.max(height, (src.height * scale).round());
    final scaled = resize(src, sw, sh);
    return cropPixels(scaled, IntRect((sw - width) ~/ 2, (sh - height) ~/ 2, width, height));
  }

  /// Dikey doğrusal renk geçişi ile tuval.
  static Raster gradient(int width, int height, int topArgb, int bottomArgb) {
    final out = Raster(width, height);
    final d = out.rgba;
    for (var y = 0; y < height; y++) {
      final t = height == 1 ? 0.0 : y / (height - 1);
      final r = clamp255(((topArgb >> 16) & 255) * (1 - t) + ((bottomArgb >> 16) & 255) * t);
      final g = clamp255(((topArgb >> 8) & 255) * (1 - t) + ((bottomArgb >> 8) & 255) * t);
      final b = clamp255((topArgb & 255) * (1 - t) + (bottomArgb & 255) * t);
      final a = clamp255(((topArgb >> 24) & 255) * (1 - t) + ((bottomArgb >> 24) & 255) * t);
      for (var x = 0; x < width; x++) {
        final i = (y * width + x) * 4;
        d[i] = r;
        d[i + 1] = g;
        d[i + 2] = b;
        d[i + 3] = a;
      }
    }
    return out;
  }

  /// Parlaklık histogramı (0..255) — otomatik ayar ve istatistik için.
  static List<int> lumaHistogram(Raster r) {
    final hist = List<int>.filled(256, 0);
    final d = r.rgba;
    final step = math.max(1, r.pixelCount ~/ 400000) * 4; // büyük görsellerde örnekleme
    for (var i = 0; i < d.length; i += step) {
      if (d[i + 3] < 16) continue;
      final l = (0.2126 * d[i] + 0.7152 * d[i + 1] + 0.0722 * d[i + 2]).round().clamp(0, 255);
      hist[l]++;
    }
    return hist;
  }
}
