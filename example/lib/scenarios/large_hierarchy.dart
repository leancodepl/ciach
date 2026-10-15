/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// A type with ten subtypes, whose members are looked up where the type is
// named rather than with a references search. Only the large-hierarchy test
// in test/finder/finder_test.dart scans this file.

/// Entry point -> USED.
void main() => print(_pick(0).area + _pick(1).describe().length);

Shape _pick(int i) => [
  Shape0(),
  Shape1(),
  Shape2(),
  Shape3(),
  Shape4(),
  Shape5(),
  Shape6(),
  Shape7(),
  Shape8(),
  Shape9(),
][i];

/// Never called -> UNUSED.
void _deadUse(Shape shape) => shape.onlyFromDead();

abstract class Shape {
  /// Read by `main` -> USED.
  int get area => _cached;

  /// Called by `main` -> USED.
  String describe() => 'shape';

  /// Never called -> UNUSED.
  void neverCalled() {}

  /// Called only by `_deadUse` -> UNUSED.
  void onlyFromDead() {}

  /// Read by `area` -> USED.
  int get _cached => 1;
}

class Shape0 extends Shape {}

class Shape1 extends Shape {}

class Shape2 extends Shape {}

class Shape3 extends Shape {}

class Shape4 extends Shape {}

class Shape5 extends Shape {}

class Shape6 extends Shape {}

class Shape7 extends Shape {}

class Shape8 extends Shape {}

class Shape9 extends Shape {}
