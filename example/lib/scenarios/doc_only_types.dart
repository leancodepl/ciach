// Fixtures for types referenced only from a doc comment. A type with unused
// members is reported once, as a whole, and never removed, so --remove cannot
// leave an empty type behind; one with nothing unused stays doc-only. Scanned
// only by the dedicated tests in test/finder_test.dart.

/// Pad the bottom yourself or use [SafeInset.new] and [SafeInset.height];
/// tint it with [Hue] or [Tinted], mix in [Padded], or mark it with [Bare].
/// Called from bin/app.dart -> USED.
void linksDocOnlyTypes() => Shade();

/// Linked only from a doc comment, with unused members -> UNUSED once, as a
/// whole; --remove keeps it.
class SafeInset {
  SafeInset();

  SafeInset.named();

  double get height => 0;

  static void reset() => _resetAll();
}

/// Called only from a member of the doc-only [SafeInset] -> USED, even under
/// --transitive.
void _resetAll() {}

/// Linked only from a doc comment, with unused members -> UNUSED once, as a
/// whole; --remove keeps it.
enum Hue { warm, cool }

/// Linked only from a doc comment, with unused members -> UNUSED once, as a
/// whole; --remove keeps it.
mixin Padded {
  void pad() {}
}

/// Linked only from a doc comment, with no members -> DOC-ONLY.
class Bare {}

/// Constructed above; its `tint` is overridden in the doc-only [Tinted] ->
/// UNUSED, but --remove keeps it with that override.
class Shade {
  void tint() {}
}

/// Linked only from a doc comment, with nothing unused -> DOC-ONLY; --remove
/// keeps its override.
class Tinted extends Shade {
  @override
  void tint() {}
}
