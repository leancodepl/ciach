// An extension and an operator overload.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Adds convenience helpers to [int] -> demonstrates extension methods.
/// Used via [doubled] -> USED (extension).
extension IntExtras on int {
  /// Referenced from bin/app.dart -> USED.
  int doubled() => this * 2;

  /// Never referenced -> UNUSED (extension method).
  int tripled() => this * 3;
}

/// A tiny 2D vector -> demonstrates operator overloading.
class Vector2 {
  const Vector2(this.x, this.y);

  final double x;
  final double y;

  /// Invoked via `+` in bin/app.dart, but the analysis server's reference
  /// search does not resolve infix operator syntax back to the declaration
  /// -> reported as UNUSED anyway (operator). See the README's Limitations
  /// section.
  Vector2 operator +(Vector2 other) => Vector2(x + other.x, y + other.y);

  /// Never referenced -> UNUSED (operator).
  Vector2 operator -(Vector2 other) => Vector2(x - other.x, y - other.y);
}
