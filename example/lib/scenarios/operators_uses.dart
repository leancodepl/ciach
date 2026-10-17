// Uses for the operator fixture: each operator in scenarios/operators.dart is
// used here, except those of `NoneUsed`, the binary `-` of `UnaryMinusOnly`,
// `Shape.+`, `Square.+` and `OnlyUsedFromDeadCode.*`.

import 'package:sample_pkg/scenarios/operators.dart';

void main() {
  const a = AllUsed(1);
  const b = AllUsed(2);
  final AllUsed sum = a + b;
  print([
    sum,
    a - b,
    -a,
    a * 2,
    a / 2,
    a % 2,
    a ~/ 2,
    a & 1,
    a | 1,
    a ^ 1,
    ~a,
    a << 1,
    a >> 1,
    a >>> 1,
    a < b,
    a <= b,
    a > b,
    a >= b,
    a[0],
  ]);
  a[0] = 1;

  print(const NoneUsed(1));
  print(-const UnaryMinusOnly());

  final counter = Counter();
  counter[0] += 1;

  var step = const Step(0);
  step++;
  step--;
  var total = const Total(0);
  total += 1;
  print([step, total]);

  print(sameLibrarySum);
  print((const Chained() + const Chained()) * 2);

  switch (const Version(2)) {
    case >= const Version(3):
      print('new');
    case Version(major: 2) && < const Version(3):
      print('two');
  }

  print(['a'] * 2);
  if (Level.low case < Level.high) {
    print('low');
  }
  print(ScaledBox() * 3);
  print(Meters(1) + Meters(2));
  print(const Box([1]) + const Box([2]));
  print(const Sub() + const Sub());
  print(const Square());
  print(const Circle() - const Circle());
  print({const Point(1)});
  print(const OnlyUsedFromDeadCode());
}
