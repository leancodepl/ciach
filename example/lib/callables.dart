// A callable class exercising the `call`-method skip.
// Expected "unused" set is asserted by test/finder_test.dart — keep in sync.

/// Demonstrates a callable class: an instance is invoked as `multiplier(v)`.
class Multiplier {
  const Multiplier(this.factor);

  /// Referenced inside the `call` method body -> USED.
  final int factor;

  /// Invoked as `multiplier(value)` in bin/app.dart. Implicit-call syntax
  /// isn't resolved back here (like operators), so it's skipped, not reported.
  int call(int value) => value * factor;
}
