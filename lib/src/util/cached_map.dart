/// Values computed from their keys on first read, then cached. A `null` value
/// is cached too, and computing one value may read others.
final class CachedMap<K, V> {
  CachedMap(this._compute);

  // Safe as long as no CachedMap is used through a wider key type.
  // ignore: unsafe_variance
  final V Function(K key) _compute;
  final _values = <K, V>{};

  /// The value for [key], computed on the first read.
  V operator [](K key) => _values.containsKey(key)
      ? _values[key] as V
      : _values[key] = _compute(key);

  /// Caches [value] for [key] in place of computing it.
  void operator []=(K key, V value) => _values[key] = value;

  /// Drops the value for [key], so the next read computes it again.
  void invalidate(K key) => _values.remove(key);
}
