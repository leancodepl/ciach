// Fixture for the enum `.values` detection fix: values reached only through
// `.values` iteration (qualified or the bare `values` getter) must count as
// USED. Each enum's type is kept alive in-file; see test/finder_test.dart.

/// Every value is reached only through `.values` iteration below, never by a
/// direct `IterableColor.<name>` reference, so all count as USED.
enum IterableColor { red, green, blue }

/// Iterates the qualified `IterableColor.values` from outside the enum, keeping
/// every value alive without naming any individually.
bool isKnownColor(String name) =>
    IterableColor.values.any((c) => c.name == name);

/// Reached through the implicit bare `values` getter inside the enum's own body
/// — the form a references query on the type never surfaces. The type is kept
/// alive by the parameter reference below; every value still counts as USED.
enum SelfIteratingUnit {
  first,
  second;

  static bool has(String name) => values.any((u) => u.name == name);
}

/// Uses the enum TYPE (keeping it alive) without naming either value.
String describeUnit(SelfIteratingUnit unit) => unit.name;
