import 'package:ciach/src/reachability.dart';
import 'package:test/test.dart';

void main() {
  Use use(int target, [List<int> enclosers = const []]) =>
      (target: target, enclosers: enclosers);

  test('a use from live code marks its target, and the chain behind it', () {
    expect(
      unreached(
        {0, 1, 2},
        [
          use(0),
          use(1, [0]),
          use(2, [1]),
        ],
      ),
      isEmpty,
    );
  });

  test('nothing marks a cycle no live code enters', () {
    expect(
      unreached(
        {0, 1},
        [
          use(0, [1]),
          use(1, [0]),
        ],
      ),
      {0, 1},
    );
  });

  test('a cycle entered from live code is marked', () {
    expect(
      unreached(
        {0, 1},
        [
          use(0, [1]),
          use(1, [0]),
          use(1),
        ],
      ),
      isEmpty,
    );
  });

  test('a use inside nested nodes needs every encloser live', () {
    // 2 is used from inside 1, which sits inside 0; only 1 is reached.
    expect(
      unreached(
        {0, 1, 2},
        [
          use(1),
          use(2, [0, 1]),
        ],
      ),
      {0, 2},
    );
    expect(
      unreached(
        {0, 1, 2},
        [
          use(0),
          use(1),
          use(2, [0, 1]),
        ],
      ),
      isEmpty,
    );
  });

  test('enclosers outside the nodes are live', () {
    expect(
      unreached(
        {0},
        [
          use(0, [7]),
        ],
      ),
      isEmpty,
    );
  });

  test('uses of nodes outside the set are ignored', () {
    expect(
      unreached(
        {0},
        [
          use(5),
          use(0, [0]),
        ],
      ),
      {0},
    );
  });

  test('the order of the uses does not matter', () {
    final uses = [
      use(3, [2]),
      use(2, [1]),
      use(1, [0]),
      use(0),
    ];
    expect(unreached({0, 1, 2, 3}, uses), isEmpty);
    expect(unreached({0, 1, 2, 3}, uses.reversed), isEmpty);
  });
}
