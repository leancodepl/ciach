// Recovery fixture. Expected findings are asserted by test/finder_test.dart;
// keep in sync.

// Named in a `show` combinator -> used, NOT flagged.
int get liveShownGetter => 1;

// Never named or used -> flagged.
int get deadUnshownGetter => 2;
