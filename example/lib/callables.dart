// A callable class and a utility class with a private constructor.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Demonstrates a callable class: an instance is invoked as `multiplier(v)`.
class Multiplier {
  const Multiplier(this.factor);

  /// Referenced inside the `call` method body -> USED.
  final int factor;

  /// Invoked as `multiplier(value)` in bin/app.dart. The analysis server does
  /// not resolve implicit-call syntax (`obj()`) back to this declaration — the
  /// same limitation as for infix operators — so it is skipped by default
  /// rather than reported as UNUSED. Never appears in the report.
  int call(int value) => value * factor;
}

/// A utility/constants class: only static members, plus a private constructor
/// to block instantiation. The constructor is intentionally never referenced,
/// so it is skipped rather than reported as UNUSED — removing it would re-add
/// the implicit default constructor and make the class instantiable.
class MathConstants {
  MathConstants._();

  /// Referenced from bin/app.dart -> USED.
  static const pi = 3.14;
}
