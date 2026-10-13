// Unused types. Each is reported once, without its members, because removing
// a type removes its members too. Only the `dead types` tests in
// test/finder_test.dart scan this file.

/// Never named -> UNUSED. Reported without its members.
class DeadBox {
  DeadBox(this.size);

  final int size;

  int doubled() => size * 2;

  static DeadBox empty() => DeadBox(0);
}

/// Never named -> UNUSED. Reported without its members.
mixin DeadTrait {
  void describe() {}

  int get weight => 1;
}

/// Never named -> UNUSED. Reported without its members.
extension type DeadId(int value) {
  int get next => value + 1;
}

/// Never named -> UNUSED. Reported without its values or members.
enum DeadLevel {
  low,
  high;

  bool get isHigh => this == high;
}
