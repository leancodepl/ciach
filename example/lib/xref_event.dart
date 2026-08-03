// Recovery fixture. Expected findings are asserted by test/finder_test.dart;
// keep in sync.

enum XrefEvent {
  // Used normally -> NOT flagged.
  signIn,

  // Used only from another file -> confirmed used, NOT flagged.
  signOut,

  // Never used -> flagged.
  deadEvent,
}
