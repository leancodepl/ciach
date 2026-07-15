// Fixture for the enum `.values` detection fix: a value reached only through
// `.values` iteration — the qualified `EnumType.values` form or the implicit
// bare `values` getter inside the enum's own body — must be treated as USED,
// so none is flagged. Self-contained (each enum's TYPE is kept alive by an
// in-file reference); scanned only by the dedicated enum-`.values` test
// (excluded from the default-run assertions); see test/finder_test.dart.

/// Every value is reached only through `.values` iteration below, never by a
/// direct `IterableColor.<name>` reference. All values must be treated as USED,
/// so none is flagged.
enum IterableColor { red, green, blue }

/// Iterates `IterableColor.values`, which keeps every value alive without
/// naming any of them individually. Uses the *qualified* `<EnumName>.values`
/// form, from outside the enum.
bool isKnownColor(String name) =>
    IterableColor.values.any((c) => c.name == name);

/// Reached through the *implicit* static `values` getter from inside the enum's
/// own body (a bare `values`, not `SelfIteratingUnit.values`) — the form a
/// `textDocument/references` query on the enum type never surfaces. The enum
/// type is kept alive by the parameter reference below; every value must still
/// be treated as USED, so none is flagged.
enum SelfIteratingUnit {
  first,
  second;

  static bool has(String name) => values.any((u) => u.name == name);
}

/// Uses the enum TYPE (keeping it alive) without naming either value.
String describeUnit(SelfIteratingUnit unit) => unit.name;
