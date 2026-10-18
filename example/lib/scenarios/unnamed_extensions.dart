/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// An unnamed extension and its members are private, whatever the members'
// names: no other library can use them. Only the unnamed-extension tests in
// test/finder/finder_test.dart scan this file.

/// Entry point -> USED.
void main() {
  2.tripled();
  print([1].second);
}

extension on int {
  int tripled() => this * 3;

  /// Never called -> UNUSED.
  int sextupled() => this * 6;

  /// Never read -> UNUSED.
  bool get isSmall => this < 10;

  /// Never written -> UNUSED.
  set ignored(int value) {}

  /// Never called -> UNUSED; only the extension itself could call it.
  static int seven() => 7;
}

extension<T> on List<T> {
  T get second => this[1];

  /// Never read -> UNUSED.
  T get third => this[2];
}

/// Never used -> UNUSED as a whole.
extension on String {
  String shouted() => toUpperCase();
}
