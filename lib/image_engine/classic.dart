import 'dart:math' as math;
import 'dart:typed_data';

import '../core/errors.dart';
import '../filters/adjustments.dart';
import 'color_matrix.dart';
import 'ops.dart';
import 'raster.dart';

/// Çevrimdışı çalışan klasik görüntü işleme algoritmaları.
///
/// Bunlar yapay zekâ DEĞİLDİR; arayüzde de öyle etiketlenir. İnternet
/// gerektirmez, fotoğraf cihazdan çıkmaz. Çevrimiçi AI sağlayıcısı
/// yapılandırılmadığında veya kullanıcı izin vermediğinde kullanılabilir.
class Classic {
  Classic._();

  // ------------------------------------------------------------ Otomatik ayar

  /// Histogram ve gri dünya varsayımından tahribatsız ayar önerisi üretir.
  static Adjustments suggestAdjustments(Raster r, Adjustments base) {
    final hist = Ops.lumaHistogram(r);
    final total = hist.fold<int>(0, (a, b) => a + b);
    if (total == 0) return base;
    int percentile(double p) {
      var acc = 0;
      final target = total * p;
      for (var i = 0; i < 256; i++) {
        acc += hist[i];
        if (acc >= target) return i;
      }
      return 255;
    }

    final lo = percentile(0.01), hi = percentile(0.99);
    var sum = 0.0;
    for (var i = 0; i < 256; i++) {
      sum += i * hist[i];
    }
    final mean = sum / total;
    final spread = math.max(1, hi - lo);

    var sr = 0.0, sg = 0.0, sb = 0.0;
    var n = 0;
    final d = r.rgba;
    final step = math.max(1, r.pixelCount ~/ 300000) * 4;
    for (var i = 0; i < d.length; i += step) {
      if (d[i + 3] < 16) continue;
      sr += d[i];
      sg += d[i + 1];
      sb += d[i + 2];
      n++;
    }
    if (n == 0) return base;
    sr /= n;
    sg /= n;
    sb /= n;
    final avg = (sr + sg + sb) / 3;

    final exposure = (math.log(118 / math.max(8, mean)) / math.ln2 * 38).clamp(-45.0, 45.0).toDouble();
    final contrast = spread < 210 ? ((210 / spread - 1) * 55).clamp(0.0, 40.0).toDouble() : 0.0;
    final temperature = avg > 1 ? ((sb - sr) / avg * 160).clamp(-35.0, 35.0).toDouble() : 0.0;
    final tint = avg > 1 ? (((sr + sb) / 2 - sg) / avg * -120).clamp(-25.0, 25.0).toDouble() : 0.0;
    final shadows = lo > 30 ? 0.0 : (mean < 100 ? 18.0 : 8.0);
    final highlights = hi > 248 ? -18.0 : 0.0;
    return base.copyWith(
      exposure: _round(exposure),
      contrast: _round(contrast),
      temperature: _round(temperature),
      tint: _round(tint),
      shadows: shadows,
      highlights: highlights,
      saturation: base.saturation == 0 ? 8 : base.saturation,
    );
  }

  static double _round(double v) => (v * 10).round() / 10;

  // ------------------------------------------------------------ İyileştirme

  /// Seviye germe + beyaz dengesi + hafif keskinlik (kalıcı uygulanır).
  static Raster enhance(Raster src) {
    final adj = suggestAdjustments(src, Adjustments.none);
    var r = src.clone();
    Ops.shadowsHighlightsInPlace(r, adj.shadows, adj.highlights);
    adj.copyWith(shadows: 0, highlights: 0).colorMatrix().applyTo(r);
    r = Ops.unsharp(r, radius: Ops.scaledRadius(r, 12), amount: 0.25);
    r = Ops.unsharp(r, radius: Ops.scaledRadius(r, 0.8), amount: 0.45, threshold: 3);
    return r;
  }

  /// Bikübik büyütme + keskinleştirme. Yapay zekâ değildir: yeni ayrıntı
  /// üretmez, yalnızca pürüzsüz büyütür.
  static Raster upscale(Raster src, int factor) {
    final f = factor.clamp(2, 4);
    final maxSide = 12000;
    var w = src.width * f, h = src.height * f;
    if (math.max(w, h) > maxSide) {
      final s = maxSide / math.max(w, h);
      w = (w * s).round();
      h = (h * s).round();
    }
    var r = Ops.resize(src, w, h);
    r = Ops.unsharp(r, radius: Ops.scaledRadius(r, 0.9), amount: 0.55, threshold: 2);
    return r;
  }

  // ------------------------------------------------------------ Portre

  static Float32List _skinMask(Raster r) {
    final n = r.pixelCount;
    final m = Raster(r.width, r.height);
    final d = r.rgba, md = m.rgba;
    for (var i = 0; i < n; i++) {
      final j = i * 4;
      final rr = d[j], gg = d[j + 1], bb = d[j + 2];
      final cb = 128 - 0.168736 * rr - 0.331264 * gg + 0.5 * bb;
      final cr = 128 + 0.5 * rr - 0.418688 * gg - 0.081312 * bb;
      final skin = cb >= 77 && cb <= 127 && cr >= 133 && cr <= 173 && d[j + 3] > 32;
      md[j] = skin ? 255 : 0;
      md[j + 3] = 255;
    }
    final blurred = Ops.boxBlur(m, Ops.scaledRadius(r, 3));
    final out = Float32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = blurred.rgba[i * 4] / 255;
    }
    return out;
  }

  /// Doğal cilt rötuşu: yalnızca ten rengi bölgelerde, kenarları koruyarak
  /// yumuşatır. Yüz algılama yoktur.
  static Raster skinSmooth(Raster src, double amount) {
    final a = amount.clamp(0.0, 1.0).toDouble();
    final mask = _skinMask(src);
    final smooth = Ops.boxBlur(src, Ops.scaledRadius(src, 4.5));
    final out = src.clone();
    final s = src.rgba, b = smooth.rgba, d = out.rgba;
    const sigma2 = 2 * 22.0 * 22.0;
    for (var i = 0; i < mask.length; i++) {
      final m = mask[i];
      if (m < 0.02) continue;
      final j = i * 4;
      final dl = (0.3 * (s[j] - b[j]) + 0.59 * (s[j + 1] - b[j + 1]) + 0.11 * (s[j + 2] - b[j + 2]));
      final edge = math.exp(-(dl * dl) / sigma2);
      final w = m * a * 0.85 * edge;
      for (var c = 0; c < 3; c++) {
        d[j + c] = clamp255(s[j + c] + (b[j + c] - s[j + c]) * w);
      }
    }
    return out;
  }

  static Raster portrait(Raster src) {
    var r = skinSmooth(src, 0.55);
    Ops.shadowsHighlightsInPlace(r, 14, -8);
    ColorMatrix.saturation(1.06).applyTo(r);
    r = Ops.unsharp(r, radius: Ops.scaledRadius(r, 0.8), amount: 0.3, threshold: 4);
    return r;
  }

  // ------------------------------------------------------------ Restorasyon

  static Raster median3(Raster src) {
    final w = src.width, h = src.height;
    final out = src.clone();
    final s = src.rgba, d = out.rgba;
    final buf = Int32List(9);
    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        for (var c = 0; c < 3; c++) {
          var k = 0;
          for (var dy = -1; dy <= 1; dy++) {
            final row = (y + dy) * w;
            for (var dx = -1; dx <= 1; dx++) {
              buf[k++] = s[(row + x + dx) * 4 + c];
            }
          }
          // 9 elemanlı ekleme sıralaması
          for (var i = 1; i < 9; i++) {
            final v = buf[i];
            var j = i - 1;
            while (j >= 0 && buf[j] > v) {
              buf[j + 1] = buf[j];
              j--;
            }
            buf[j + 1] = v;
          }
          d[(y * w + x) * 4 + c] = buf[4];
        }
      }
    }
    return out;
  }

  /// Eski fotoğraf restorasyonu: gürültü/toz azaltma, solmuş renk ve
  /// kontrastın geri kazanımı. Yırtık veya eksik bölgeler için "Nesne silme"
  /// fırçası kullanılmalıdır.
  static Raster restore(Raster src) {
    var r = median3(src);
    r = enhance(r);
    return r;
  }

  // ------------------------------------------------------------ Sanatsal stiller

  static Raster style(Raster src, String styleId) {
    switch (styleId) {
      case 'oil':
        return _kuwahara(src, Ops.scaledRadius(src, 3.2));
      case 'sketch':
        return _sketch(src);
      case 'cartoon':
        return _cartoon(src);
      case 'pop':
        return _pop(src);
      default:
        throw UserFacingException('Bilinmeyen stil: $styleId');
    }
  }

  static const Map<String, String> styleNames = {
    'oil': 'Yağlı boya',
    'sketch': 'Karakalem',
    'cartoon': 'Çizgi film',
    'pop': 'Pop art',
  };

  static Raster _kuwahara(Raster src, int r) {
    final w = src.width, h = src.height, n = w * h;
    final s = src.rgba;
    // Sol-üst köşeye sabitlenmiş (r+1)x(r+1) kutu ortalamaları.
    final k = r + 1;
    final meanR = Uint8List(n), meanG = Uint8List(n), meanB = Uint8List(n);
    final meanL = Float32List(n), meanL2 = Float32List(n);
    final rowR = Float64List(n), rowG = Float64List(n), rowB = Float64List(n), rowL = Float64List(n), rowL2 = Float64List(n);
    for (var y = 0; y < h; y++) {
      var aR = 0.0, aG = 0.0, aB = 0.0, aL = 0.0, aL2 = 0.0;
      for (var x = 0; x < k && x < w; x++) {
        final i = (y * w + x) * 4;
        final l = 0.299 * s[i] + 0.587 * s[i + 1] + 0.114 * s[i + 2];
        aR += s[i];
        aG += s[i + 1];
        aB += s[i + 2];
        aL += l;
        aL2 += l * l;
      }
      for (var x = 0; x < w; x++) {
        final o = y * w + x;
        rowR[o] = aR;
        rowG[o] = aG;
        rowB[o] = aB;
        rowL[o] = aL;
        rowL2[o] = aL2;
        final xo = x, xi = x + k;
        if (xi < w) {
          final io = (y * w + xo) * 4, ii = (y * w + xi) * 4;
          final lo = 0.299 * s[io] + 0.587 * s[io + 1] + 0.114 * s[io + 2];
          final li = 0.299 * s[ii] + 0.587 * s[ii + 1] + 0.114 * s[ii + 2];
          aR += s[ii] - s[io];
          aG += s[ii + 1] - s[io + 1];
          aB += s[ii + 2] - s[io + 2];
          aL += li - lo;
          aL2 += li * li - lo * lo;
        }
      }
    }
    for (var x = 0; x < w; x++) {
      var aR = 0.0, aG = 0.0, aB = 0.0, aL = 0.0, aL2 = 0.0;
      for (var y = 0; y < k && y < h; y++) {
        final o = y * w + x;
        aR += rowR[o];
        aG += rowG[o];
        aB += rowB[o];
        aL += rowL[o];
        aL2 += rowL2[o];
      }
      for (var y = 0; y < h; y++) {
        final o = y * w + x;
        final cntX = math.min(k, w - x);
        final cntY = math.min(k, h - y);
        final cnt = (cntX * cntY).toDouble();
        meanR[o] = clamp255(aR / cnt);
        meanG[o] = clamp255(aG / cnt);
        meanB[o] = clamp255(aB / cnt);
        meanL[o] = aL / cnt;
        meanL2[o] = aL2 / cnt;
        final yi = y + k;
        if (yi < h) {
          final oi = yi * w + x;
          aR += rowR[oi] - rowR[o];
          aG += rowG[oi] - rowG[o];
          aB += rowB[oi] - rowB[o];
          aL += rowL[oi] - rowL[o];
          aL2 += rowL2[oi] - rowL2[o];
        }
      }
    }
    final out = Raster(w, h);
    final d = out.rgba;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        var best = -1;
        var bestVar = double.infinity;
        for (var q = 0; q < 4; q++) {
          final ax = ((q & 1) == 0 ? x - r : x).clamp(0, w - 1);
          final ay = ((q & 2) == 0 ? y - r : y).clamp(0, h - 1);
          final o = ay * w + ax;
          final v = meanL2[o] - meanL[o] * meanL[o];
          if (v < bestVar) {
            bestVar = v;
            best = o;
          }
        }
        final i = (y * w + x) * 4;
        d[i] = meanR[best];
        d[i + 1] = meanG[best];
        d[i + 2] = meanB[best];
        d[i + 3] = s[i + 3];
      }
    }
    return out;
  }

  static Raster _sketch(Raster src) {
    final gray = src.clone();
    ColorMatrix.grayscale().applyTo(gray);
    final inv = gray.clone();
    ColorMatrix.invert().applyTo(inv);
    final blurred = Ops.boxBlur(inv, Ops.scaledRadius(src, 7));
    final out = Raster(src.width, src.height);
    final g = gray.rgba, b = blurred.rgba, d = out.rgba;
    for (var i = 0; i < d.length; i += 4) {
      final base = g[i];
      final blend = b[i];
      final v = blend >= 255 ? 255 : math.min(255, base * 255 ~/ (255 - blend));
      final shaded = clamp255(v * 0.92 + 8);
      d[i] = shaded;
      d[i + 1] = shaded;
      d[i + 2] = shaded;
      d[i + 3] = src.rgba[i + 3];
    }
    return out;
  }

  static void _posterizeInPlace(Raster r, int levels) {
    final step = 255 / (levels - 1);
    final d = r.rgba;
    for (var i = 0; i < d.length; i += 4) {
      for (var c = 0; c < 3; c++) {
        d[i + c] = clamp255((d[i + c] / step).round() * step);
      }
    }
  }

  static Raster _cartoon(Raster src) {
    var smooth = median3(src);
    smooth = Ops.boxBlur(smooth, Ops.scaledRadius(src, 1.2), passes: 2);
    final out = smooth.clone();
    _posterizeInPlace(out, 7);
    ColorMatrix.saturation(1.25).applyTo(out);
    // Sobel kenarları
    final w = src.width, h = src.height;
    final s = smooth.rgba, d = out.rgba;
    double lum(int x, int y) {
      final i = (y * w + x) * 4;
      return 0.299 * s[i] + 0.587 * s[i + 1] + 0.114 * s[i + 2];
    }

    for (var y = 1; y < h - 1; y++) {
      for (var x = 1; x < w - 1; x++) {
        final gx = -lum(x - 1, y - 1) - 2 * lum(x - 1, y) - lum(x - 1, y + 1) + lum(x + 1, y - 1) + 2 * lum(x + 1, y) + lum(x + 1, y + 1);
        final gy = -lum(x - 1, y - 1) - 2 * lum(x, y - 1) - lum(x + 1, y - 1) + lum(x - 1, y + 1) + 2 * lum(x, y + 1) + lum(x + 1, y + 1);
        final mag = math.sqrt(gx * gx + gy * gy);
        if (mag > 90) {
          final i = (y * w + x) * 4;
          final k = mag > 160 ? 0.15 : 0.45;
          d[i] = clamp255(d[i] * k);
          d[i + 1] = clamp255(d[i + 1] * k);
          d[i + 2] = clamp255(d[i + 2] * k);
        }
      }
    }
    return out;
  }

  static Raster _pop(Raster src) {
    final out = src.clone();
    ColorMatrix.contrast(1.3).compose(ColorMatrix.saturation(1.9)).applyTo(out);
    _posterizeInPlace(out, 4);
    return out;
  }

  // ------------------------------------------------------------ Nesne silme (inpainting)

  /// Fırça darbelerini tam çözünürlük maskesine dönüştürür (0/255).
  /// [strokes]: her biri [yarıçap, x0, y0, x1, y1, ...] (belge pikseli).
  static Uint8List rasterizeStrokes(int width, int height, List<List<double>> strokes, {double scale = 1}) {
    final mask = Uint8List(width * height);
    for (final s in strokes) {
      if (s.length < 3) continue;
      final radius = s[0] * scale + 1.5;
      final pts = <double>[for (var i = 1; i < s.length; i++) s[i] * scale];
      if (pts.length == 2) pts.addAll([pts[0], pts[1]]);
      for (var i = 0; i + 3 < pts.length; i += 2) {
        _capsule(mask, width, height, pts[i], pts[i + 1], pts[i + 2], pts[i + 3], radius);
      }
    }
    return mask;
  }

  static void _capsule(Uint8List m, int w, int h, double x0, double y0, double x1, double y1, double r) {
    final minX = (math.min(x0, x1) - r).floor().clamp(0, w - 1);
    final maxX = (math.max(x0, x1) + r).ceil().clamp(0, w - 1);
    final minY = (math.min(y0, y1) - r).floor().clamp(0, h - 1);
    final maxY = (math.max(y0, y1) + r).ceil().clamp(0, h - 1);
    final dx = x1 - x0, dy = y1 - y0;
    final len2 = dx * dx + dy * dy;
    final r2 = r * r;
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        var t = len2 == 0 ? 0.0 : ((x - x0) * dx + (y - y0) * dy) / len2;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
        final px = x0 + t * dx - x, py = y0 + t * dy - y;
        if (px * px + py * py <= r2) m[y * w + x] = 255;
      }
    }
  }

  /// Çok ölçekli difüzyon ile maske altındaki alanı çevresinden doldurur.
  static Raster inpaint(Raster src, Uint8List mask) {
    final w0 = src.width, h0 = src.height;
    var masked = 0;
    for (final v in mask) {
      if (v != 0) masked++;
    }
    if (masked == 0) throw const UserFacingException('Silinecek alanı fırçayla boyayın.');
    if (masked > w0 * h0 * 0.6) {
      throw const UserFacingException('Seçilen alan çok büyük. Görselin %60\'ından küçük bir alan seçin.');
    }

    // Seviye 0: float görüntü ve bilinen/bilinmeyen bayrağı.
    final levelsImg = <Float32List>[];
    final levelsKnown = <Uint8List>[];
    final levelsW = <int>[], levelsH = <int>[];
    final img0 = Float32List(w0 * h0 * 4);
    final known0 = Uint8List(w0 * h0);
    for (var i = 0; i < w0 * h0; i++) {
      known0[i] = mask[i] == 0 ? 1 : 0;
      for (var c = 0; c < 4; c++) {
        img0[i * 4 + c] = src.rgba[i * 4 + c].toDouble();
      }
    }
    levelsImg.add(img0);
    levelsKnown.add(known0);
    levelsW.add(w0);
    levelsH.add(h0);

    // Piramit: bilinmeyen kalmayana kadar küçült.
    while (true) {
      final w = levelsW.last, h = levelsH.last;
      final known = levelsKnown.last;
      var unknown = 0;
      for (final k in known) {
        if (k == 0) unknown++;
      }
      if (unknown == 0 || w <= 4 || h <= 4) break;
      final nw = (w + 1) ~/ 2, nh = (h + 1) ~/ 2;
      final src2 = levelsImg.last;
      final dst = Float32List(nw * nh * 4);
      final dk = Uint8List(nw * nh);
      for (var y = 0; y < nh; y++) {
        for (var x = 0; x < nw; x++) {
          var cnt = 0;
          final acc = [0.0, 0.0, 0.0, 0.0];
          for (var dy = 0; dy < 2; dy++) {
            for (var dx = 0; dx < 2; dx++) {
              final sx = x * 2 + dx, sy = y * 2 + dy;
              if (sx >= w || sy >= h) continue;
              final si = sy * w + sx;
              if (known[si] == 0) continue;
              cnt++;
              for (var c = 0; c < 4; c++) {
                acc[c] += src2[si * 4 + c];
              }
            }
          }
          final di = y * nw + x;
          if (cnt > 0) {
            dk[di] = 1;
            for (var c = 0; c < 4; c++) {
              dst[di * 4 + c] = acc[c] / cnt;
            }
          }
        }
      }
      levelsImg.add(dst);
      levelsKnown.add(dk);
      levelsW.add(nw);
      levelsH.add(nh);
    }

    // En kaba seviyede soğan kabuğu doldurma.
    {
      final w = levelsW.last, h = levelsH.last;
      final im = levelsImg.last;
      final known = Uint8List.fromList(levelsKnown.last);
      var remaining = known.where((k) => k == 0).length;
      var guard = 0;
      while (remaining > 0 && guard++ < 10000) {
        final toSet = <int>[];
        final values = <double>[];
        for (var y = 0; y < h; y++) {
          for (var x = 0; x < w; x++) {
            final i = y * w + x;
            if (known[i] != 0) continue;
            var cnt = 0;
            final acc = [0.0, 0.0, 0.0, 0.0];
            for (var dy = -1; dy <= 1; dy++) {
              for (var dx = -1; dx <= 1; dx++) {
                final nx = x + dx, ny = y + dy;
                if (nx < 0 || ny < 0 || nx >= w || ny >= h) continue;
                final ni = ny * w + nx;
                if (known[ni] == 0) continue;
                cnt++;
                for (var c = 0; c < 4; c++) {
                  acc[c] += im[ni * 4 + c];
                }
              }
            }
            if (cnt > 0) {
              toSet.add(i);
              for (var c = 0; c < 4; c++) {
                values.add(acc[c] / cnt);
              }
            }
          }
        }
        if (toSet.isEmpty) break;
        for (var t = 0; t < toSet.length; t++) {
          final i = toSet[t];
          for (var c = 0; c < 4; c++) {
            im[i * 4 + c] = values[t * 4 + c];
          }
          known[i] = 1;
        }
        remaining -= toSet.length;
      }
    }

    // Yukarı doğru: kaba seviyeden başlat, Jacobi yumuşatma ile pürüzsüzleştir.
    for (var lvl = levelsImg.length - 2; lvl >= 0; lvl--) {
      final w = levelsW[lvl], h = levelsH[lvl];
      final cw = levelsW[lvl + 1], ch = levelsH[lvl + 1];
      final im = levelsImg[lvl];
      final coarse = levelsImg[lvl + 1];
      final known = levelsKnown[lvl];
      final unknownIdx = <int>[];
      for (var i = 0; i < w * h; i++) {
        if (known[i] == 0) unknownIdx.add(i);
      }
      for (final i in unknownIdx) {
        final x = i % w, y = i ~/ w;
        final fx = ((x + 0.5) / 2 - 0.5).clamp(0.0, cw - 1.0).toDouble();
        final fy = ((y + 0.5) / 2 - 0.5).clamp(0.0, ch - 1.0).toDouble();
        final x0 = fx.floor(), y0 = fy.floor();
        final x1 = math.min(x0 + 1, cw - 1), y1 = math.min(y0 + 1, ch - 1);
        final tx = fx - x0, ty = fy - y0;
        for (var c = 0; c < 4; c++) {
          final a = coarse[(y0 * cw + x0) * 4 + c], b = coarse[(y0 * cw + x1) * 4 + c];
          final cc = coarse[(y1 * cw + x0) * 4 + c], dd = coarse[(y1 * cw + x1) * 4 + c];
          im[i * 4 + c] = (a + (b - a) * tx) + ((cc + (dd - cc) * tx) - (a + (b - a) * tx)) * ty;
        }
      }
      final iterations = lvl == 0 ? 24 : 12;
      for (var it = 0; it < iterations; it++) {
        for (final i in unknownIdx) {
          final x = i % w, y = i ~/ w;
          var cnt = 0;
          final acc = [0.0, 0.0, 0.0, 0.0];
          if (x > 0) {
            cnt++;
            for (var c = 0; c < 4; c++) {
              acc[c] += im[(i - 1) * 4 + c];
            }
          }
          if (x < w - 1) {
            cnt++;
            for (var c = 0; c < 4; c++) {
              acc[c] += im[(i + 1) * 4 + c];
            }
          }
          if (y > 0) {
            cnt++;
            for (var c = 0; c < 4; c++) {
              acc[c] += im[(i - w) * 4 + c];
            }
          }
          if (y < h - 1) {
            cnt++;
            for (var c = 0; c < 4; c++) {
              acc[c] += im[(i + w) * 4 + c];
            }
          }
          for (var c = 0; c < 4; c++) {
            im[i * 4 + c] = acc[c] / cnt;
          }
        }
      }
    }

    // Doku: maske çevresindeki gürültü düzeyine göre hafif gren ekle.
    final out = src.clone();
    final im = levelsImg[0];
    var varSum = 0.0;
    var varCnt = 0;
    final rnd = math.Random(4242);
    for (var i = 0; i < w0 * h0; i += 7) {
      if (mask[i] != 0) continue;
      final x = i % w0;
      if (x == 0 || x == w0 - 1) continue;
      final dl = src.rgba[i * 4 + 1] - (src.rgba[(i - 1) * 4 + 1] + src.rgba[(i + 1) * 4 + 1]) / 2;
      varSum += dl * dl;
      varCnt++;
    }
    final noise = varCnt > 0 ? math.min(10.0, math.sqrt(varSum / varCnt) * 0.6) : 0.0;
    for (var i = 0; i < w0 * h0; i++) {
      if (mask[i] == 0) continue;
      final n = noise > 0 ? (rnd.nextDouble() + rnd.nextDouble() - 1) * noise : 0.0;
      for (var c = 0; c < 3; c++) {
        out.rgba[i * 4 + c] = clamp255(im[i * 4 + c] + n);
      }
      out.rgba[i * 4 + 3] = clamp255(im[i * 4 + 3]);
    }
    return out;
  }

  // ------------------------------------------------------------ Arka plan

  /// Düz/tek renkli arka planı kenarlardan taşma (flood fill) ile kaldırır.
  /// [tolerance] 5..100. Karmaşık arka planlar için çevrimiçi AI gerekir.
  static Raster removeUniformBackground(Raster src, {double tolerance = 32}) {
    final w = src.width, h = src.height, n = w * h;
    final s = src.rgba;
    // Kenar piksellerinden referans renk (kanal başına medyan).
    final rs = <int>[], gs = <int>[], bs = <int>[];
    void sample(int x, int y) {
      final i = (y * w + x) * 4;
      rs.add(s[i]);
      gs.add(s[i + 1]);
      bs.add(s[i + 2]);
    }

    final stepX = math.max(1, w ~/ 200), stepY = math.max(1, h ~/ 200);
    for (var x = 0; x < w; x += stepX) {
      sample(x, 0);
      sample(x, h - 1);
    }
    for (var y = 0; y < h; y += stepY) {
      sample(0, y);
      sample(w - 1, y);
    }
    int median(List<int> v) {
      v.sort();
      return v[v.length ~/ 2];
    }

    final refR = median(rs), refG = median(gs), refB = median(bs);
    final tol = tolerance.clamp(5, 100) * 1.6;
    final tol2 = tol * tol;
    bool similar(int i) {
      final j = i * 4;
      final dr = s[j] - refR, dg = s[j + 1] - refG, db = s[j + 2] - refB;
      return dr * dr + dg * dg + db * db <= tol2 || s[j + 3] < 8;
    }

    final bg = Uint8List(n);
    final queue = Int32List(n);
    var head = 0, tail = 0;
    void seed(int i) {
      if (bg[i] == 0 && similar(i)) {
        bg[i] = 1;
        queue[tail++] = i;
      }
    }

    for (var x = 0; x < w; x++) {
      seed(x);
      seed((h - 1) * w + x);
    }
    for (var y = 0; y < h; y++) {
      seed(y * w);
      seed(y * w + w - 1);
    }
    while (head < tail) {
      final i = queue[head++];
      final x = i % w, y = i ~/ w;
      if (x > 0) seed(i - 1);
      if (x < w - 1) seed(i + 1);
      if (y > 0) seed(i - w);
      if (y < h - 1) seed(i + w);
    }
    final ratio = tail / n;
    if (ratio < 0.02) {
      throw const UserFacingException(
          'Düz bir arka plan algılanamadı. Bu yöntem tek renkli/stüdyo arka planlar içindir; karmaşık arka planlar için '
          'Ayarlar > AI sağlayıcıları bölümünden çevrimiçi bir sağlayıcı yapılandırın.');
    }
    if (ratio > 0.985) {
      throw const UserFacingException('Görselin neredeyse tamamı arka plan olarak algılandı. Toleransı düşürün.');
    }
    // Yumuşak kenar: maskeyi bulanıklaştır.
    final m = Raster(w, h);
    for (var i = 0; i < n; i++) {
      m.rgba[i * 4] = bg[i] == 1 ? 0 : 255;
      m.rgba[i * 4 + 3] = 255;
    }
    final soft = Ops.boxBlur(m, Ops.scaledRadius(src, 0.7), passes: 2);
    final out = src.clone();
    for (var i = 0; i < n; i++) {
      final a = soft.rgba[i * 4];
      out.rgba[i * 4 + 3] = (s[i * 4 + 3] * a) ~/ 255;
    }
    return out;
  }

  /// Şeffaf alanları renk, geçiş veya başka bir görselle doldurur.
  static Raster replaceBackground(Raster cutout, {int? topArgb, int? bottomArgb, Raster? image}) {
    if (!cutout.hasTransparency) {
      throw const UserFacingException('Görselde şeffaf alan yok. Önce "Arka plan kaldır" işlemini uygulayın.');
    }
    Raster bg;
    if (image != null) {
      bg = Ops.cover(image, cutout.width, cutout.height);
    } else {
      final top = topArgb ?? 0xFFFFFFFF;
      bg = Ops.gradient(cutout.width, cutout.height, top, bottomArgb ?? top);
    }
    return Ops.compositeOver(cutout, bg);
  }

  /// Alfa maskesini (0..255, gri) görüntüye uygular — çevrimiçi
  /// segmentasyon sonuçları için.
  static Raster applyAlphaMask(Raster src, Raster mask) {
    final m = (mask.width == src.width && mask.height == src.height) ? mask : Ops.resize(mask, src.width, src.height);
    final out = src.clone();
    for (var i = 0; i < src.pixelCount; i++) {
      final j = i * 4;
      // Maske gri tonlu veya alfa kanallı olabilir.
      final mv = m.rgba[j + 3] < 255 ? m.rgba[j + 3] : m.rgba[j];
      out.rgba[j + 3] = (src.rgba[j + 3] * mv) ~/ 255;
    }
    return out;
  }
}
