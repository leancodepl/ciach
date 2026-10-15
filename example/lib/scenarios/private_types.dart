/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Members of a private class are private, whatever their own names. Only the
// `private types` test in test/finder/finder_test.dart scans this file.

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
