// Dead extensions and extension types. An extension is dead only once every
// member is; an extension type is a type, dead when nothing names it. Either
// is then reported whole. Scanned with extensions_emptied_uses.dart by its own
// test.

/// Nothing names it or calls a member -> UNUSED (extension).
extension DeadHelpers on int {
  int first() => this + 1;
  int second() => this + 2;
}

/// `alive` is called -> USED; only `stale` is reported.
extension LiveHelpers on int {
  int alive() => this * 2;

  int stale() => this * 3;
}

/// Both members dead -> UNUSED (extension), under the server's placeholder name.
extension on String {
  String shoutedOnce() => '$this!';
  String shoutedTwice() => '$this!!';
}

/// Named in a `show` -> the extension stays; only the member is reported.
extension ShownHelpers on int {
  int shownButUnused() => this - 1;
}

/// No members, no references -> UNUSED (extension).
extension Hollow on int {}

/// Nothing names it -> UNUSED (extension type), reported whole like a dead
/// class, with its dead members alongside it.
extension type DeadMeters(int value) {
  int get scaled => value * 2;
}

/// Only its own body names it -> UNUSED (extension type).
extension type SelfMeters(int value) {
  SelfMeters get next => SelfMeters(value + 1);
}

/// Named as a type by [toMeters] -> USED.
extension type Meters(int value) {}

Meters toMeters(int value) => Meters(value);
