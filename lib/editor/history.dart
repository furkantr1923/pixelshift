/// Çok adımlı geri al / yinele yığını.
///
/// Belgeler değişmez olduğu için her adım yalnızca bir referanstır;
/// bellek maliyeti düşüktür. [limit] aşıldığında en eski adımlar atılır.
class History<T> {
  History(T initial, {this.limit = 100}) : _items = [initial], _labels = ['Açılış'];

  final int limit;
  final List<T> _items;
  final List<String> _labels;
  int _index = 0;

  T get current => _items[_index];
  int get index => _index;
  int get length => _items.length;
  bool get canUndo => _index > 0;
  bool get canRedo => _index < _items.length - 1;
  String? get undoLabel => canUndo ? _labels[_index] : null;
  String? get redoLabel => canRedo ? _labels[_index + 1] : null;
  List<T> get items => List.unmodifiable(_items);
  List<String> get labels => List.unmodifiable(_labels);

  void push(T value, String label) {
    if (_index < _items.length - 1) {
      _items.removeRange(_index + 1, _items.length);
      _labels.removeRange(_index + 1, _labels.length);
    }
    _items.add(value);
    _labels.add(label);
    _index = _items.length - 1;
    while (_items.length > limit) {
      _items.removeAt(0);
      _labels.removeAt(0);
      _index--;
    }
  }

  /// Son adımı yeni değerle değiştirir (ör. aynı kaydırıcının art arda değişimi).
  void replaceCurrent(T value) {
    _items[_index] = value;
  }

  T undo() {
    if (canUndo) _index--;
    return current;
  }

  T redo() {
    if (canRedo) _index++;
    return current;
  }

  /// Projeden geri yükleme.
  void restore(List<T> items, List<String> labels, int index) {
    if (items.isEmpty) return;
    _items
      ..clear()
      ..addAll(items);
    _labels
      ..clear()
      ..addAll(labels.length == items.length ? labels : List.filled(items.length, 'Düzenleme'));
    _index = index.clamp(0, items.length - 1);
  }
}
