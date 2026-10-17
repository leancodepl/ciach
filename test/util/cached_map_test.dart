import 'package:ciach/src/util/cached_map.dart';
import 'package:test/test.dart';

void main() {
  test('computes each value once', () {
    final computed = <String>[];
    final lengths = CachedMap<String, int>((key) {
      computed.add(key);
      return key.length;
    });
    expect([lengths['ab'], lengths['abc'], lengths['ab']], [2, 3, 2]);
    expect(computed, ['ab', 'abc']);
  });

  test('caches a null value', () {
    var calls = 0;
    final values = CachedMap<String, int?>((_) {
      calls++;
      return null;
    });
    expect([values['a'], values['a']], [null, null]);
    expect(calls, 1);
  });

  test('lets a value read others', () {
    late final CachedMap<int, int> sums;
    sums = .new((n) => n == 0 ? 0 : n + sums[n - 1]);
    expect(sums[4], 10);
    expect(sums[3], 6);
  });

  test('calling the map reads the cached value', () {
    var calls = 0;
    final lengths = CachedMap<String, int>((key) {
      calls++;
      return key.length;
    });
    expect(['ab', 'ab'].map(lengths), [2, 2]);
    expect(calls, 1);
  });

  test('keeps a set value and recomputes an invalidated one', () {
    var calls = 0;
    final values = CachedMap<String, int>((_) => ++calls);
    values['a'] = 7;
    expect(values['a'], 7);
    values.invalidate('a');
    expect(values['a'], 1);
  });
}
