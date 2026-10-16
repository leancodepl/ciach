// A callable class whose `call` method is used only by invoking an instance.
// Expected "unused" set is asserted by test/finder_test.dart — keep in sync.

/// Demonstrates a callable class: an instance is invoked as `multiplier(v)`.
class Multiplier {
  const Multiplier(this.factor);

  /// Referenced inside the `call` method body -> USED.
  final int factor;

  /// Invoked as `multiplier(value)` in bin/app.dart, which the server reports
  /// no reference for; ciach still finds the use -> USED.
  int call(int value) => value * factor;
}
