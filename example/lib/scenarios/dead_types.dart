// Dead types, each reported once: its dead members go with it. Scanned only by
// the dedicated tests (excluded from the default-run assertions); see
// test/finder_test.dart.

/// Never named -> UNUSED, reported alone.
class DeadBox {
  DeadBox(this.size);

  final int size;

  int doubled() => size * 2;

  static DeadBox empty() => DeadBox(0);
}

/// Never named -> UNUSED, reported alone.
mixin DeadTrait {
  void describe() {}

  int get weight => 1;
}

/// Never named -> UNUSED, reported alone.
extension type DeadId(int value) {
  int get next => value + 1;
}

/// Never named -> UNUSED, reported alone with its values.
enum DeadLevel {
  low,
  high;

  bool get isHigh => this == high;
}
