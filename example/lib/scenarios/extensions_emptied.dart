// Dead extensions: one is dead only once every member is, and is then reported
// whole. Scanned with extensions_emptied_uses.dart by its own test.

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

/// An `extension type` is never a candidate.
extension type Meters(int value) {}

Meters toMeters(int value) => Meters(value);
