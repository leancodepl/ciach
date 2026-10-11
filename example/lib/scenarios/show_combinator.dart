// Recovery fixture. Expected findings are asserted by test/finder_test.dart;
// keep in sync.

// Find-references misses a top-level getter named in a `show`.
export 'show_combinator_src.dart' show liveShownGetter;
