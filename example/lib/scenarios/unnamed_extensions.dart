/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Members of an unnamed extension are private, whatever their own names: no
// other library can call them. Only the unnamed-extension tests in
// test/finder/finder_test.dart scan this file.

/// Entry point -> USED.
void main() => 2.tripled();

extension on int {
  int tripled() => this * 3;

  /// Never called -> UNUSED, private: no other library can use an unnamed
  /// extension.
  int sextupled() => this * 6;
}
