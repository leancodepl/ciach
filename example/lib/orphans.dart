// Two classes that are never referenced at all -> a whole-file "orphan".
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Never referenced anywhere -> UNUSED (class).
class UnusedClass {
  /// Method of an unused class; also never referenced -> UNUSED.
  void orphanMethod() {}
}

/// Never instantiated, so its unnamed constructor is UNUSED and reported as
/// `Unconstructed.new`. The class itself is not reported: the analysis server
/// treats the explicit constructor's declaration as a use of the class name.
class Unconstructed {
  Unconstructed();
}
