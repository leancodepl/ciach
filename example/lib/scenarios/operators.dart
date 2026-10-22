// Operators and their uses, which are in operators_uses.dart. Only
// test/finder/operators_test.dart scans these files.
// Expected findings: every operator of NoneUsed, the binary `-` of
// UnaryMinusOnly, Ordered.>, Shape.+, Square.+, onlyFromDeadCode and
// OnlyUsedFromDeadCode.*.

/// Declares every operator that a class can declare but `==`, and
/// operators_uses.dart uses each of them.
class AllUsed {
  const AllUsed(this.value);

  final int value;

  AllUsed operator +(AllUsed other) => AllUsed(value + other.value);
  AllUsed operator -(AllUsed other) => AllUsed(value - other.value);
  AllUsed operator -() => AllUsed(-value);
  AllUsed operator *(int factor) => AllUsed(value * factor);
  AllUsed operator /(int divisor) => AllUsed(value ~/ divisor);
  AllUsed operator %(int divisor) => AllUsed(value % divisor);
  AllUsed operator ~/(int divisor) => AllUsed(value ~/ divisor);
  AllUsed operator &(int mask) => AllUsed(value & mask);
  AllUsed operator |(int mask) => AllUsed(value | mask);
  AllUsed operator ^(int mask) => AllUsed(value ^ mask);
  AllUsed operator ~() => AllUsed(~value);
  AllUsed operator <<(int shift) => AllUsed(value << shift);
  AllUsed operator >>(int shift) => AllUsed(value >> shift);
  AllUsed operator >>>(int shift) => AllUsed(value >>> shift);
  bool operator <(AllUsed other) => value < other.value;
  bool operator <=(AllUsed other) => value <= other.value;
  bool operator >(AllUsed other) => value > other.value;
  bool operator >=(AllUsed other) => value >= other.value;
  int operator [](int index) => value;
  void operator []=(int index, int newValue) {}
}

/// Constructed, but none of its operators is used.
class NoneUsed {
  const NoneUsed(this.value);

  final int value;

  NoneUsed operator +(NoneUsed other) => NoneUsed(value + other.value);
  NoneUsed operator -(NoneUsed other) => NoneUsed(value - other.value);
  NoneUsed operator -() => NoneUsed(-value);
  NoneUsed operator *(int factor) => NoneUsed(value * factor);
  NoneUsed operator /(int divisor) => NoneUsed(value ~/ divisor);
  NoneUsed operator %(int divisor) => NoneUsed(value % divisor);
  NoneUsed operator ~/(int divisor) => NoneUsed(value ~/ divisor);
  NoneUsed operator &(int mask) => NoneUsed(value & mask);
  NoneUsed operator |(int mask) => NoneUsed(value | mask);
  NoneUsed operator ^(int mask) => NoneUsed(value ^ mask);
  NoneUsed operator ~() => NoneUsed(~value);
  NoneUsed operator <<(int shift) => NoneUsed(value << shift);
  NoneUsed operator >>(int shift) => NoneUsed(value >> shift);
  NoneUsed operator >>>(int shift) => NoneUsed(value >>> shift);
  bool operator <(NoneUsed other) => value < other.value;
  bool operator <=(NoneUsed other) => value <= other.value;
  bool operator >(NoneUsed other) => value > other.value;
  bool operator >=(NoneUsed other) => value >= other.value;
  int operator [](int index) => value;
  void operator []=(int index, int newValue) {}
}

/// Only the unary `-` is used.
class UnaryMinusOnly {
  const UnaryMinusOnly();

  UnaryMinusOnly operator -() => this;
  UnaryMinusOnly operator -(UnaryMinusOnly other) => this;
}

/// Used only as `counter[i] += 1`, which reads with `[]` and writes with
/// `[]=`.
class Counter {
  final _counts = <int>[0];

  int operator [](int index) => _counts[index];
  void operator []=(int index, int count) => _counts[index] = count;
}

/// Its `+` is used only by `++`, and its `-` only by `--`.
class Step {
  const Step(this.value);

  final int value;

  Step operator +(int by) => Step(value + by);
  Step operator -(int by) => Step(value - by);
}

/// Used only with `+=`.
class Total {
  const Total(this.value);

  final int value;

  Total operator +(int by) => Total(value + by);
}

/// Used only in this library.
class SameLibrary {
  const SameLibrary();

  SameLibrary operator +(SameLibrary other) => this;
}

final sameLibrarySum = const SameLibrary() + const SameLibrary();

/// Its `*` is used only on the result of its `+`, as in `(a + b) * 2`.
class Chained {
  const Chained();

  Chained operator +(Chained other) => this;
  Chained operator *(int factor) => this;
}

/// Used only in relational patterns.
class Version {
  const Version(this.major);

  final int major;

  bool operator <(Version other) => major < other.major;
  bool operator >=(Version other) => major >= other.major;
}

extension Repeat on List<String> {
  List<String> operator *(int times) => [
    for (var i = 0; i < times; i++) ...this,
  ];
}

enum Level {
  low,
  high;

  bool operator <(Level other) => index < other.index;
}

/// Only its `<` is used.
class Ordered {
  const Ordered(this.rank);

  final int rank;

  bool operator <(Ordered other) => rank < other.rank;
  bool operator >(Ordered other) => rank > other.rank;
}

mixin Scaled {
  int get size;

  int operator *(int factor) => size * factor;
}

class ScaledBox with Scaled {
  @override
  int get size => 2;
}

extension type Meters(double value) {
  Meters operator +(Meters other) => Meters(value + other.value);
}

class Box<T> {
  const Box(this.items);

  final List<T> items;

  Box<T> operator +(Box<T> other) => Box([...items, ...other.items]);
}

/// Its `+` is used only through [Sub], which inherits it.
class Base {
  const Base();

  Base operator +(Base other) => this;
}

class Sub extends Base {
  const Sub();
}

/// [Square] overrides `+`, and no code uses either. With `--also overrides`,
/// both are reported.
abstract class Shape {
  const Shape();

  Shape operator +(Shape other);
}

class Square extends Shape {
  const Square();

  @override
  Shape operator +(Shape other) => this;
}

/// [Circle] overrides `-`, and code uses only the override.
abstract class Round {
  const Round();

  Round operator -(Round other);
}

class Circle extends Round {
  const Circle();

  @override
  Round operator -(Round other) => this;
}

/// [Both] overrides `+` of [Left] and of [Right], and code uses `+` only
/// through [Both].
abstract class Left {
  const Left();

  Left operator +(Left other);
}

abstract class Right {
  Left operator +(Left other);
}

class Both extends Left implements Right {
  const Both();

  @override
  Left operator +(Left other) => this;
}

/// Only `UnscannedOverride`, in a file that no test scans, overrides `~`, and
/// code uses `~` only through it.
abstract class OverriddenElsewhere {
  const OverriddenElsewhere();

  OverriddenElsewhere operator ~();
}

/// Its `==` is never reported, even with `--also overrides`: the SDK calls it
/// from `Set`, `Map` and `List.contains`.
class Point {
  const Point(this.x);

  final int x;

  @override
  bool operator ==(Object other) => other is Point && other.x == x;

  @override
  int get hashCode => x.hashCode;
}

/// Its `*` is used only by `onlyFromDeadCode`, which nothing calls.
class OnlyUsedFromDeadCode {
  const OnlyUsedFromDeadCode();

  OnlyUsedFromDeadCode operator *(int factor) => this;
}

OnlyUsedFromDeadCode onlyFromDeadCode() => const OnlyUsedFromDeadCode() * 2;
