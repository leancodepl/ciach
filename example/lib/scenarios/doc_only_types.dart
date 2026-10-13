// Fixtures for types that only doc comments mention. A type with unused
// members is reported once, as the type, and --remove does not delete it. This
// way --remove cannot leave an empty type behind. A type with no unused
// members is reported as doc-only. Only tests in test/finder_test.dart scan
// this file.

/// Mentions [SafeInset.new], [SafeInset.height], [Hue], [Tinted], [Padded]
/// and [Bare].
/// Called from bin/app.dart -> USED.
void linksDocOnlyTypes() => Shade();

/// Only a doc comment mentions it, and its members are unused -> UNUSED once,
/// as the type. --remove keeps it.
class SafeInset {
  SafeInset();

  SafeInset.named();

  double get height => 0;

  static void reset() => _resetAll();
}

/// Called only from a member of [SafeInset] -> USED, also with --transitive.
void _resetAll() {}

/// Only a doc comment mentions it, and its members are unused -> UNUSED once,
/// as the type. --remove keeps it.
enum Hue { warm, cool }

/// Only a doc comment mentions it, and its members are unused -> UNUSED once,
/// as the type. --remove keeps it.
mixin Padded {
  void pad() {}
}

/// Only a doc comment mentions it, and it has no members -> DOC-ONLY.
class Bare {}

/// Constructed above. Its `tint` -> UNUSED, but --remove keeps it because
/// the override in [Tinted] stays.
class Shade {
  void tint() {}
}

/// Only a doc comment mentions it, and nothing in it is unused -> DOC-ONLY.
/// --remove keeps its override.
class Tinted extends Shade {
  @override
  void tint() {}
}
