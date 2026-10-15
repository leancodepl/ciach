/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// A private class that a public function hands out. Only the private-class
// tests in test/finder/finder_test.dart scan this file.

/// Public: another package can call `makeTool().use()`.
_Tool makeTool() => _Tool();

class _Tool {
  /// Reachable through `makeTool` -> KEPT when the package is exported.
  void use() {}

  /// Unreachable from outside this file -> UNUSED.
  void _spare() {}
}
