/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// A member of a private type whose only use in the files that name the type
// is dead, while a live use elsewhere names only a public function. Only the
// private-type tests in test/finder/finder_test.dart scan this file and
// private_probe_use.dart.

/// Hands `_Probed` out -> USED by private_probe_use.dart.
_Probed makeProbed() => _Probed();

/// Never called -> UNUSED.
void _deadUse() => _Probed().probe();

class _Probed {
  /// Called by `_deadUse`, which is dead, and by private_probe_use.dart
  /// through `makeProbed` -> USED.
  void probe() {}
}
