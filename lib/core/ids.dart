import 'dart:math' as math;

final math.Random _random = math.Random();

/// Çakışma olasılığı ihmal edilebilir, dosya adına uygun kimlik.
String newId([String prefix = 'id']) {
  final t = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = _random.nextInt(1 << 32).toRadixString(36).padLeft(7, '0');
  return '${prefix}_$t$r';
}
