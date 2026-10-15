/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Members of a private class are private, whatever their own names. Only the
// private-class tests in test/finder/finder_test.dart scan this file.

/// Entry point -> USED.
void main() => _Settings.defaults().used;

/// Constructed by `main` -> USED.
class _Settings {
  /// Never called -> UNUSED, private through its class.
  _Settings();

  _Settings.defaults();

  int used = 0;

  /// Never called -> UNUSED, private through its class.
  void reset() {}
}
