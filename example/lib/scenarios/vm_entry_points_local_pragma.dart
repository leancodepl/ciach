/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

// A `pragma` class of the project's own, which hides the one from
// `dart:core` in this library, keeps nothing. Expected findings:
// `localPragma` and `pragma`, whose only user is `localPragma`.
//
// Scanned only by the dedicated test; see
// test/finder/vm_entry_points_test.dart.

// ignore: camel_case_types, matches the name of the class in `dart:core`.
class pragma {
  const pragma(this.name);

  final String name;
}

/// Annotated with this library's `pragma` -> UNUSED (function).
@pragma('vm:entry-point')
void localPragma() {}
