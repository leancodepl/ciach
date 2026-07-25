// Fixture for cross-library reference recovery — dot-shorthands (issue #25).
//
// The expected findings are asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

enum XrefEvent {
  // Referenced normally (imported) in xref_analytics.dart -> NOT flagged.
  signIn,

  // Referenced ONLY via a cross-library dot-shorthand in xref_uses.dart, whose
  // library does not import this one -> recovered, NOT flagged (#25).
  signOut,

  // Never referenced anywhere -> genuinely dead, MUST still be flagged.
  deadEvent,
}
