// Classes exercising whole-class deadness and constructor reporting.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Never referenced anywhere -> UNUSED (class). Reported once for the class;
/// its method is also unused and reported separately.
class UnusedClass {
  /// Method of an unused class; also never referenced -> UNUSED.
  void orphanMethod() {}
}

/// Never referenced anywhere, and never constructed. The analysis server still
/// reports the class's own explicit unnamed constructor declaration as a
/// "reference" to the class name (their name ranges coincide), so a naive
/// reference search sees the class as "used" and flags only the constructor —
/// which, if removed on its own, would strand the class and break the build.
/// The dead-class detection sees through that self-reference and reports the
/// whole CLASS as unused instead, as `FullyDeadClass`. Its `FullyDeadClass.new`
/// constructor is deliberately not reported separately: removing the class
/// removes the constructor with it.
class FullyDeadClass {
  const FullyDeadClass();
}

/// Referenced only as a *type* from bin/app.dart, but never constructed. The
/// class itself is therefore USED (a real reference exists outside it) and is
/// never flagged; only its unnamed constructor is unused, reported as
/// `ReferencedAsTypeOnly.new`.
class ReferencedAsTypeOnly {
  ReferencedAsTypeOnly();
}
