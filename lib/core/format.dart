/// Türkçe biçimlendirme yardımcıları (intl bağımlılığı olmadan).
String formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1).replaceAll('.', ',')} KB';
  if (bytes < 1024 * 1024 * 1024) return '${(bytes / 1024 / 1024).toStringAsFixed(1).replaceAll('.', ',')} MB';
  return '${(bytes / 1024 / 1024 / 1024).toStringAsFixed(2).replaceAll('.', ',')} GB';
}

const List<String> _months = [
  'Ocak', 'Şubat', 'Mart', 'Nisan', 'Mayıs', 'Haziran', //
  'Temmuz', 'Ağustos', 'Eylül', 'Ekim', 'Kasım', 'Aralık',
];

String formatDateTime(DateTime t) {
  final local = t.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '${local.day} ${_months[local.month - 1]} ${local.year}, $hh:$mm';
}

String formatRelative(DateTime t, {DateTime? now}) {
  final n = now ?? DateTime.now();
  final d = n.difference(t);
  if (d.inSeconds < 60) return 'az önce';
  if (d.inMinutes < 60) return '${d.inMinutes} dakika önce';
  if (d.inHours < 24) return '${d.inHours} saat önce';
  if (d.inDays < 7) return '${d.inDays} gün önce';
  return formatDateTime(t);
}

String formatDuration(Duration d) {
  final s = d.inMilliseconds / 1000;
  if (s < 60) return '${s.toStringAsFixed(1).replaceAll('.', ',')} sn';
  return '${d.inMinutes} dk ${d.inSeconds % 60} sn';
}

String formatMegapixels(int w, int h) => '${(w * h / 1e6).toStringAsFixed(1).replaceAll('.', ',')} MP';

/// Türkçe büyük/küçük harf dönüşümü (i/İ, ı/I).
String trLower(String s) => s.replaceAll('I', 'ı').replaceAll('İ', 'i').toLowerCase();

/// Dosya adı için güvenli hâle getirir.
String safeFileName(String name, {String fallback = 'pixelshift'}) {
  var s = name.trim().replaceAll(RegExp(r'[\\/:*?"<>|\x00-\x1f]'), '_');
  if (s.length > 80) s = s.substring(0, 80);
  if (s.isEmpty || s == '.' || s == '..') return fallback;
  return s;
}
