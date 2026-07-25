// Cross-library reference-recovery fixture (dot-shorthands). Expected findings
// are asserted by test/finder_test.dart; keep in sync.

enum XrefEvent {
  // Referenced normally (imported) -> NOT flagged.
  signIn,

  // Used only via a cross-library dot-shorthand -> recovered, NOT flagged.
  signOut,

  // Never referenced -> still flagged.
  deadEvent,
}
