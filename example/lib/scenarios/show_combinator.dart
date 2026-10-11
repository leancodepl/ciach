// Combinator fixture. Expected findings are asserted by test/finder_test.dart;
// keep in sync.

// Names `liveShownGetter` in a `show`, which find-references misses for a
// top-level getter.
export 'show_combinator_src.dart' show liveShownGetter;
