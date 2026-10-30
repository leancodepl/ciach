/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// Declarations that `@pragma('vm:entry-point')` marks for native code or
// reflection. Expected findings: `Host.helper`, `inlined` and
// `deprecatedMention`.
//
// Scanned only by the dedicated test; see
// test/finder/vm_entry_points_test.dart.

/// Kept, because the VM calls `callback` on it.
class Host {
  @pragma('vm:entry-point')
  void callback() {}

  /// Nothing marks it -> UNUSED (method).
  void helper() {}
}

@pragma('vm:entry-point', 'call')
void withSecondArgument() {}

/// Another `pragma` value keeps nothing -> UNUSED (function).
@pragma('vm:prefer-inline')
void inlined() {}

/// `vm:entry-point` in another annotation keeps nothing -> UNUSED (function).
@Deprecated('vm:entry-point')
void deprecatedMention() {}
