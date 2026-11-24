import 'dart:typed_data';

import 'raster.dart';

/// Saf Dart WebP (VP8L, kayıpsız) kodlayıcı.
///
/// `image` paketi WebP'yi yalnızca çözebildiği için PIXELSHIFT kendi
/// kodlayıcısını içerir. Windows ve Android'de aynı kod çalışır, yerel
/// kütüphane gerektirmez.
///
/// Uygulanan özellikler (WebP Lossless Bitstream Specification):
/// - Yeşil çıkarma (subtract green) dönüşümü
/// - Blok başına en uygun kipin seçildiği tahmin (predictor) dönüşümü
/// - LZ77 geri referansları (karma zinciri ile)
/// - Uzunluk sınırlı kanonik Huffman kodları
///
/// [nearLosslessBits] > 0 ise pikseller kodlamadan önce düşük bitlerde
/// yuvarlanır ("yakın-kayıpsız"): dosya küçülür, gözle görülür fark azdır.
class WebpEncoder {
  WebpEncoder._();

  static Uint8List encode(Raster raster, {int nearLosslessBits = 0}) {
    final w = raster.width, h = raster.height;
    if (w > 16384 || h > 16384) {
      throw ArgumentError('WebP en fazla 16384 piksel kenar uzunluğunu destekler.');
    }
    final src = raster.rgba;
    final n = w * h;
    final px = Uint32List(n);
    var hasAlpha = false;
    final q = nearLosslessBits.clamp(0, 3);
    for (var i = 0, j = 0; i < n; i++, j += 4) {
      var r = src[j], g = src[j + 1], b = src[j + 2];
      final a = src[j + 3];
      if (q > 0) {
        r = _quant(r, q);
        g = _quant(g, q);
        b = _quant(b, q);
      }
      if (a != 255) hasAlpha = true;
      px[i] = (a << 24) | (r << 16) | (g << 8) | b;
    }

    final bw = _BitWriter();
    bw.put(0x2f, 8);
    bw.put(w - 1, 14);
    bw.put(h - 1, 14);
    bw.put(hasAlpha ? 1 : 0, 1);
    bw.put(0, 3);

    // 1) Yeşil çıkarma
    bw.put(1, 1);
    bw.put(2, 2);
    for (var i = 0; i < n; i++) {
      final p = px[i];
      final g = (p >> 8) & 255;
      final r = (((p >> 16) & 255) - g) & 255;
      final b = ((p & 255) - g) & 255;
      px[i] = (p & 0xff00ff00) | (r << 16) | b;
    }

    // 2) Tahmin dönüşümü (çok küçük görsellerde atlanır)
    var data = px;
    if (w >= 2 && h >= 2) {
      const bits = 4;
      const bs = 1 << bits;
      final tw = (w + bs - 1) >> bits;
      final th = (h + bs - 1) >> bits;
      final modes = Uint8List(tw * th);
      for (var ty = 0; ty < th; ty++) {
        for (var tx = 0; tx < tw; tx++) {
          var bestCost = -1;
          var bestMode = 1;
          for (final m in _modes) {
            var cost = 0;
            final yEnd = ((ty + 1) * bs).clamp(0, h);
            final xEnd = ((tx + 1) * bs).clamp(0, w);
            for (var y = ty * bs; y < yEnd; y++) {
              if (y == 0) continue;
              for (var x = tx * bs; x < xEnd; x++) {
                if (x == 0) continue;
                final p = px[y * w + x];
                final pr = _predict(m, px[y * w + x - 1], px[(y - 1) * w + x], px[(y - 1) * w + x - 1]);
                final r = _sub(p, pr);
                cost += _absCost(r & 255) +
                    _absCost((r >> 8) & 255) +
                    _absCost((r >> 16) & 255) +
                    _absCost((r >> 24) & 255);
              }
              if (bestCost >= 0 && cost >= bestCost) break;
            }
            if (bestCost < 0 || cost < bestCost) {
              bestCost = cost;
              bestMode = m;
            }
          }
          modes[ty * tw + tx] = bestMode;
        }
      }
      final res = Uint32List(n);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final i = y * w + x;
          final p = px[i];
          int pr;
          if (y == 0 && x == 0) {
            pr = 0xff000000;
          } else if (y == 0) {
            pr = px[i - 1];
          } else if (x == 0) {
            pr = px[i - w];
          } else {
            pr = _predict(modes[(y >> bits) * tw + (x >> bits)], px[i - 1], px[i - w], px[i - w - 1]);
          }
          res[i] = _sub(p, pr);
        }
      }
      bw.put(1, 1);
      bw.put(0, 2);
      bw.put(bits - 2, 3);
      final sub = Uint32List(tw * th);
      for (var i = 0; i < sub.length; i++) {
        sub[i] = 0xff000000 | (modes[i] << 8);
      }
      _writeImageData(bw, sub, tw, th, isMain: false);
      data = res;
    }

    bw.put(0, 1); // başka dönüşüm yok
    _writeImageData(bw, data, w, h, isMain: true);
    final payload = bw.finish();

    final pad = payload.length.isOdd ? 1 : 0;
    final chunkSize = payload.length;
    final riffSize = 4 + 8 + chunkSize + pad;
    final out = BytesBuilder(copy: false);
    out.add(const [0x52, 0x49, 0x46, 0x46]); // RIFF
    out.add(_u32(riffSize));
    out.add(const [0x57, 0x45, 0x42, 0x50]); // WEBP
    out.add(const [0x56, 0x50, 0x38, 0x4c]); // VP8L
    out.add(_u32(chunkSize));
    out.add(payload);
    if (pad == 1) out.addByte(0);
    return out.toBytes();
  }

  /// Kalite (1..100) -> yakın-kayıpsız bit sayısı.
  static int bitsForQuality(int quality) {
    if (quality >= 100) return 0;
    if (quality >= 85) return 1;
    return 2;
  }

  static int _quant(int v, int bits) {
    final half = 1 << (bits - 1);
    final mask = ~((1 << bits) - 1);
    final q = (v + half) & mask;
    return q > 255 ? 255 & mask : q;
  }

  static Uint8List _u32(int v) => Uint8List.fromList([v & 255, (v >> 8) & 255, (v >> 16) & 255, (v >> 24) & 255]);

  static const List<int> _modes = [1, 2, 7, 11, 12, 13];

  static int _absCost(int v) => v < 128 ? v : 256 - v;

  static int _sub(int a, int b) {
    final ra = (((a >> 24) & 255) - ((b >> 24) & 255)) & 255;
    final rr = (((a >> 16) & 255) - ((b >> 16) & 255)) & 255;
    final rg = (((a >> 8) & 255) - ((b >> 8) & 255)) & 255;
    final rb = ((a & 255) - (b & 255)) & 255;
    return (ra << 24) | (rr << 16) | (rg << 8) | rb;
  }

  static int _avg2(int a, int b) {
    return ((((a >> 24) & 255) + ((b >> 24) & 255)) >> 1) << 24 |
        ((((a >> 16) & 255) + ((b >> 16) & 255)) >> 1) << 16 |
        ((((a >> 8) & 255) + ((b >> 8) & 255)) >> 1) << 8 |
        (((a & 255) + (b & 255)) >> 1);
  }

  static int _clamp(int v) => v < 0 ? 0 : (v > 255 ? 255 : v);

  static int _select(int l, int t, int tl) {
    var pL = 0, pT = 0;
    for (var s = 0; s < 32; s += 8) {
      final ts = (t >> s) & 255, ls = (l >> s) & 255, tls = (tl >> s) & 255;
      pL += (ts - tls).abs();
      pT += (ls - tls).abs();
    }
    return pL < pT ? l : t;
  }

  static int _casFull(int a, int b, int c) {
    var out = 0;
    for (var s = 0; s < 32; s += 8) {
      out |= _clamp(((a >> s) & 255) + ((b >> s) & 255) - ((c >> s) & 255)) << s;
    }
    return out;
  }

  static int _casHalf(int a, int b) {
    var out = 0;
    for (var s = 0; s < 32; s += 8) {
      final x = (a >> s) & 255, y = (b >> s) & 255;
      out |= _clamp(x + (x - y) ~/ 2) << s; // ~/ sıfıra doğru keser (C ile aynı)
    }
    return out;
  }

  static int _predict(int mode, int l, int t, int tl) {
    switch (mode) {
      case 1:
        return l;
      case 2:
        return t;
      case 7:
        return _avg2(l, t);
      case 11:
        return _select(l, t, tl);
      case 12:
        return _casFull(l, t, tl);
      case 13:
        return _casHalf(_avg2(l, t), tl);
      default:
        return 0xff000000;
    }
  }

  // ------------------------------------------------------------ Entropi kodlama

  static void _writeImageData(_BitWriter bw, Uint32List px, int w, int h, {required bool isMain}) {
    bw.put(0, 1); // renk önbelleği yok
    if (isMain) bw.put(0, 1); // tek prefix kod grubu

    final n = px.length;
    // Belirteçler: literal -> kind 0, value; geri referans -> kind 1, len, dist
    final kinds = Uint8List(n);
    final vals = Uint32List(n);
    final dists = Uint32List(n);
    var tokenCount = 0;

    const hashBits = 18;
    const hashSize = 1 << hashBits;
    const chainLimit = 8;
    const maxDist = (1 << 20) - 120;
    final head = Int32List(hashSize)..fillRange(0, hashSize, -1);
    final prev = Int32List(n);

    int hashAt(int i) {
      final a = px[i], b = px[i + 1];
      var x = (a * 0x9E3779B1 + b * 0x85EBCA77) & 0xffffffff;
      x ^= x >> 15;
      return x & (hashSize - 1);
    }

    void insert(int i) {
      if (i + 1 >= n) return;
      final hv = hashAt(i);
      prev[i] = head[hv];
      head[hv] = i;
    }

    int matchLen(int i, int d) {
      var l = 0;
      final maxL = (n - i) < 4096 ? n - i : 4096;
      while (l < maxL && px[i + l] == px[i + l - d]) {
        l++;
      }
      return l;
    }

    var i = 0;
    while (i < n) {
      var bestLen = 0, bestDist = 0;
      if (i > 0 && i + 1 < n) {
        // Doğrudan adaylar: önceki piksel (tekrar) ve bir üst satır.
        for (final d in [1, w]) {
          if (d <= i && d <= maxDist) {
            final l = matchLen(i, d);
            if (l > bestLen) {
              bestLen = l;
              bestDist = d;
            }
          }
        }
        var cand = head[hashAt(i)];
        var steps = 0;
        while (cand >= 0 && steps < chainLimit) {
          final d = i - cand;
          if (d > maxDist) break;
          if (d > 0) {
            final l = matchLen(i, d);
            if (l > bestLen) {
              bestLen = l;
              bestDist = d;
              if (l >= 4096) break;
            }
          }
          cand = prev[cand];
          steps++;
        }
      }
      if (bestLen >= 3) {
        kinds[tokenCount] = 1;
        vals[tokenCount] = bestLen;
        dists[tokenCount] = bestDist;
        tokenCount++;
        for (var k = 0; k < bestLen; k++) {
          insert(i + k);
        }
        i += bestLen;
      } else {
        kinds[tokenCount] = 0;
        vals[tokenCount] = px[i];
        tokenCount++;
        insert(i);
        i++;
      }
    }

    final cg = Int32List(256 + 24), cr = Int32List(256), cb = Int32List(256), ca = Int32List(256), cd = Int32List(40);
    for (var t = 0; t < tokenCount; t++) {
      if (kinds[t] == 0) {
        final p = vals[t];
        cg[(p >> 8) & 255]++;
        cr[(p >> 16) & 255]++;
        cb[p & 255]++;
        ca[(p >> 24) & 255]++;
      } else {
        cg[256 + _prefix(vals[t]).code]++;
        cd[_prefix(dists[t] + 120).code]++;
      }
    }
    final hg = _writeHuffman(bw, cg);
    final hr = _writeHuffman(bw, cr);
    final hb = _writeHuffman(bw, cb);
    final ha = _writeHuffman(bw, ca);
    final hd = _writeHuffman(bw, cd);

    for (var t = 0; t < tokenCount; t++) {
      if (kinds[t] == 0) {
        final p = vals[t];
        final g = (p >> 8) & 255, r = (p >> 16) & 255, b = p & 255, a = (p >> 24) & 255;
        bw.put(hg.codes[g], hg.lengths[g]);
        bw.put(hr.codes[r], hr.lengths[r]);
        bw.put(hb.codes[b], hb.lengths[b]);
        bw.put(ha.codes[a], ha.lengths[a]);
      } else {
        final lp = _prefix(vals[t]);
        bw.put(hg.codes[256 + lp.code], hg.lengths[256 + lp.code]);
        bw.put(lp.extraValue, lp.extraBits);
        final dp = _prefix(dists[t] + 120);
        bw.put(hd.codes[dp.code], hd.lengths[dp.code]);
        bw.put(dp.extraValue, dp.extraBits);
      }
    }
  }

  static _Prefix _prefix(int v) {
    final d = v - 1;
    if (d < 4) return _Prefix(d, 0, 0);
    final hb = d.bitLength - 1;
    final second = (d >> (hb - 1)) & 1;
    final eb = hb - 1;
    return _Prefix(2 * hb + second, eb, d & ((1 << eb) - 1));
  }

  static const List<int> _clOrder = [17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15];

  static _Huffman _writeHuffman(_BitWriter bw, Int32List counts) {
    final n = counts.length;
    final nz = <int>[];
    for (var i = 0; i < n; i++) {
      if (counts[i] > 0) nz.add(i);
    }
    if (nz.length <= 2 && nz.every((s) => s < 256)) {
      final syms = nz.isEmpty ? [0] : nz;
      bw.put(1, 1);
      bw.put(syms.length - 1, 1);
      if (syms[0] < 2) {
        bw.put(0, 1);
        bw.put(syms[0], 1);
      } else {
        bw.put(1, 1);
        bw.put(syms[0], 8);
      }
      if (syms.length == 2) bw.put(syms[1], 8);
      final lengths = Int32List(n), codes = Int32List(n);
      if (syms.length == 2) {
        lengths[syms[0]] = 1;
        lengths[syms[1]] = 1;
        codes[syms[0]] = 0;
        codes[syms[1]] = 1;
      }
      return _Huffman(lengths, codes);
    }

    final lengths = _huffmanLengths(counts, 15);
    final codes = _canonicalCodes(lengths);

    // Kod uzunluklarını RLE belirteçlerine çevir.
    final tokSym = <int>[], tokExtra = <int>[], tokBits = <int>[];
    void tok(int s, int e, int b) {
      tokSym.add(s);
      tokExtra.add(e);
      tokBits.add(b);
    }

    var i = 0, prevLen = 8;
    while (i < n) {
      final l = lengths[i];
      var run = 1;
      while (i + run < n && lengths[i + run] == l) {
        run++;
      }
      var r = run;
      if (l == 0) {
        while (r > 0) {
          if (r < 3) {
            for (var k = 0; k < r; k++) {
              tok(0, 0, 0);
            }
            r = 0;
          } else if (r <= 10) {
            tok(17, r - 3, 3);
            r = 0;
          } else {
            final k = r < 138 ? r : 138;
            tok(18, k - 11, 7);
            r -= k;
          }
        }
      } else {
        if (l != prevLen) {
          tok(l, 0, 0);
          r--;
          prevLen = l;
        }
        while (r > 0) {
          if (r < 3) {
            for (var k = 0; k < r; k++) {
              tok(l, 0, 0);
            }
            r = 0;
          } else {
            final k = r < 6 ? r : 6;
            tok(16, k - 3, 2);
            r -= k;
          }
        }
        prevLen = l;
      }
      i += run;
    }

    final clCounts = Int32List(19);
    for (final s in tokSym) {
      clCounts[s]++;
    }
    var clLengths = _huffmanLengths(clCounts, 7);
    final used = [for (var s = 0; s < 19; s++) if (clCounts[s] > 0) s];
    if (used.length == 1) {
      clLengths = Int32List(19);
      clLengths[used[0]] = 1;
      clLengths[used[0] != 0 ? 0 : 1] = 1;
    }
    final clCodes = _canonicalCodes(clLengths);
    var codeCount = 19;
    while (codeCount > 4 && clLengths[_clOrder[codeCount - 1]] == 0) {
      codeCount--;
    }
    bw.put(0, 1); // normal kod
    bw.put(codeCount - 4, 4);
    for (var k = 0; k < codeCount; k++) {
      bw.put(clLengths[_clOrder[k]], 3);
    }
    bw.put(0, 1); // max_symbol = alfabe boyutu
    for (var t = 0; t < tokSym.length; t++) {
      final s = tokSym[t];
      bw.put(clCodes[s], clLengths[s]);
      if (tokBits[t] > 0) bw.put(tokExtra[t], tokBits[t]);
    }
    // Tek sembollü kod: çözücü 0 bitlik kod kabul eder.
    if (nz.length == 1) return _Huffman(Int32List(n), Int32List(n));
    return _Huffman(lengths, codes);
  }

  static Int32List _huffmanLengths(Int32List counts, int limit) {
    final n = counts.length;
    final lengths = Int32List(n);
    final nz = <int>[];
    for (var i = 0; i < n; i++) {
      if (counts[i] > 0) nz.add(i);
    }
    if (nz.isEmpty) return lengths;
    if (nz.length == 1) {
      lengths[nz[0]] = 1;
      return lengths;
    }
    final c = Int64List(n);
    for (final i in nz) {
      c[i] = counts[i];
    }
    while (true) {
      // Düğümler: 0..n-1 yapraklar, n.. iç düğümler
      final weight = <int>[];
      final parent = <int>[];
      final heap = _MinHeap();
      for (final i in nz) {
        weight.add(c[i]);
        parent.add(-1);
        heap.push(c[i], weight.length - 1, weight.length - 1);
      }
      final leafCount = weight.length;
      var order = leafCount;
      while (heap.length > 1) {
        final a = heap.pop();
        final b = heap.pop();
        weight.add(weight[a] + weight[b]);
        parent.add(-1);
        final id = weight.length - 1;
        parent[a] = id;
        parent[b] = id;
        heap.push(weight[id], order++, id);
      }
      var maxLen = 0;
      for (var k = 0; k < leafCount; k++) {
        var d = 0, node = k;
        while (parent[node] >= 0) {
          node = parent[node];
          d++;
        }
        lengths[nz[k]] = d;
        if (d > maxLen) maxLen = d;
      }
      if (maxLen <= limit) return lengths;
      var total = 0;
      for (final i in nz) {
        total += c[i];
      }
      var thr = total >> (limit - 2);
      if (thr < 1) thr = 1;
      for (final i in nz) {
        if (c[i] < thr) c[i] = thr;
      }
    }
  }

  static Int32List _canonicalCodes(Int32List lengths) {
    var maxLen = 0;
    for (final l in lengths) {
      if (l > maxLen) maxLen = l;
    }
    final blCount = Int32List(maxLen + 2);
    for (final l in lengths) {
      if (l > 0) blCount[l]++;
    }
    final nextCode = Int32List(maxLen + 2);
    var code = 0;
    for (var b = 1; b <= maxLen; b++) {
      code = (code + blCount[b - 1]) << 1;
      nextCode[b] = code;
    }
    final codes = Int32List(lengths.length);
    for (var i = 0; i < lengths.length; i++) {
      final l = lengths[i];
      if (l == 0) continue;
      var c = nextCode[l]++;
      var r = 0;
      for (var k = 0; k < l; k++) {
        r = (r << 1) | (c & 1);
        c >>= 1;
      }
      codes[i] = r;
    }
    return codes;
  }
}

class _Prefix {
  const _Prefix(this.code, this.extraBits, this.extraValue);
  final int code;
  final int extraBits;
  final int extraValue;
}

class _Huffman {
  const _Huffman(this.lengths, this.codes);
  final Int32List lengths;
  final Int32List codes;
}

/// (ağırlık, sıra) çiftine göre küçük-yığın; düğüm kimliğini döndürür.
class _MinHeap {
  final List<int> _w = [];
  final List<int> _o = [];
  final List<int> _id = [];

  int get length => _w.length;

  bool _less(int a, int b) => _w[a] < _w[b] || (_w[a] == _w[b] && _o[a] < _o[b]);

  void _swap(int a, int b) {
    var t = _w[a];
    _w[a] = _w[b];
    _w[b] = t;
    t = _o[a];
    _o[a] = _o[b];
    _o[b] = t;
    t = _id[a];
    _id[a] = _id[b];
    _id[b] = t;
  }

  void push(int weight, int order, int id) {
    _w.add(weight);
    _o.add(order);
    _id.add(id);
    var i = _w.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_less(i, p)) {
        _swap(i, p);
        i = p;
      } else {
        break;
      }
    }
  }

  int pop() {
    final top = _id[0];
    final last = _w.length - 1;
    _swap(0, last);
    _w.removeLast();
    _o.removeLast();
    _id.removeLast();
    var i = 0;
    while (true) {
      final l = 2 * i + 1, r = l + 1;
      var m = i;
      if (l < _w.length && _less(l, m)) m = l;
      if (r < _w.length && _less(r, m)) m = r;
      if (m == i) break;
      _swap(i, m);
      i = m;
    }
    return top;
  }
}

class _BitWriter {
  final BytesBuilder _out = BytesBuilder(copy: false);
  final Uint8List _chunk = Uint8List(65536);
  int _pos = 0;
  int _acc = 0;
  int _n = 0;

  void put(int value, int nbits) {
    if (nbits == 0) return;
    _acc |= value << _n;
    _n += nbits;
    while (_n >= 8) {
      _chunk[_pos++] = _acc & 255;
      if (_pos == _chunk.length) {
        _out.add(Uint8List.fromList(_chunk));
        _pos = 0;
      }
      _acc >>= 8;
      _n -= 8;
    }
  }

  Uint8List finish() {
    if (_n > 0) {
      _chunk[_pos++] = _acc & 255;
      _acc = 0;
      _n = 0;
    }
    if (_pos > 0) _out.add(Uint8List.sublistView(_chunk, 0, _pos));
    return _out.toBytes();
  }
}
