// Fixture for dead extensions: an extension is used only through its members,
// never by name, so one whose every member is dead is dead itself and is
// reported (and removed) whole rather than left behind as an empty
// `extension E on T {}` once its members go. Scanned only by its own test
// (excluded from the default-run assertions); see test/finder_test.dart.
//
// extensions_emptied_uses.dart imports this file with a `show`, which is the
// one way to refer to an extension by name.

/// Never referenced by name, and neither member is called -> UNUSED, reported
/// as the whole EXTENSION; `first` and `second` are not findings of their own.
extension DeadHelpers on int {
  int first() => this + 1;
  int second() => this + 2;
}

/// `alive` is called from extensions_emptied_uses.dart, so the extension is
/// USED even though nothing names `LiveHelpers` -> not reported. Its dead
/// member is reported on its own, like any method.
extension LiveHelpers on int {
  int alive() => this * 2;

  /// Never referenced -> UNUSED (method).
  int stale() => this * 3;
}

/// Nothing can refer to an unnamed extension by name; both members are dead ->
/// UNUSED, reported as the whole EXTENSION.
extension on String {
  String shoutedOnce() => '$this!';
  String shoutedTwice() => '$this!!';
}

/// Every member is dead, but extensions_emptied_uses.dart names the extension
/// in a `show` combinator -> the extension stays (dropping it would break the
/// import); only the member is reported.
extension ShownHelpers on int {
  /// Never referenced -> UNUSED (method).
  int shownButUnused() => this - 1;
}

/// No members and no references -> UNUSED (extension).
extension Hollow on int {}

/// Referenced as a type below, so used; an `extension type` is a type, not an
/// extension, and is never a candidate -> not reported.
extension type Meters(int value) {}

/// Keeps [Meters] alive.
Meters toMeters(int value) => Meters(value);
