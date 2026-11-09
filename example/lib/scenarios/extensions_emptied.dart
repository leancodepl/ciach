// Dead extensions and extension types, each reported whole. Scanned with
// extensions_emptied_uses.dart by its own test.

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

/// Nothing names it, but [main] calls `measure` -> USED. Its local function
/// and `_base`, which only `measure` calls, don't make the extension dead.
extension LocalHelpers on int {
  int measure() {
    int doubled(int n) => n * 2;
    return doubled(_base());
  }

  int _base() => this;
}

/// Both members dead -> UNUSED. The server names it `extension on String`.
extension on String {
  String shoutedOnce() => '$this!';
  String shoutedTwice() => '$this!!';
}

/// Named in a `show` -> stays; only the member is reported.
extension ShownHelpers on int {
  int shownButUnused() => this - 1;
}

/// No members, no references -> UNUSED (extension).
extension Hollow on int {}

/// Unnamed and generic, so its type parameters sit where a name would ->
/// UNUSED (extension).
extension<T> on List<T> {
  T? get firstOrNothing => isEmpty ? null : first;
}

/// A bound with its own generics must not end the type parameters early ->
/// UNUSED (extension).
extension<T extends Map<String, List<int>>> on T {
  int get deadNested => length;
}

/// Nothing names it -> UNUSED (extension type), with its dead members.
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

/// Nothing but a doc comment names it, and [main] calls `percent` -> USED.
extension DocNamedHelpers on int {
  int percent() => this * 100;
}

/// Prints [DocNamedHelpers.percent] and `measure` of 21.
void main() => print(21.percent() + 21.measure());
