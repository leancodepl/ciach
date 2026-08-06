// Fixture for dot-shorthand (`.name`) detection. Each member documented below
// as "reached only as `.x`" is reachable from outside this file ONLY through a
// shorthand, from exactly one kind of shorthand context, so a context the
// reference search cannot see surfaces as exactly one finding. The uses live in
// scenarios/dot_shorthand_uses.dart; expected findings are asserted by
// test/finder_test.dart — keep in sync.
//
// Nothing here iterates `Weight.values`, nor names a bare `values` inside the
// enum body: either would mark every value used (see enum_values.dart) and hide
// whatever the shorthand detection misses.

/// One value per shorthand context, written as `.value` at its use site and
/// never as `Weight.value`.
enum Weight {
  // Argument positions.
  positional,
  named,

  // Initializers, returns, and yields.
  variableInit,
  fieldInit,
  arrowReturn,
  blockReturn,
  asyncReturn,
  yielded,

  // Collection, record, and map literals.
  listElement,
  setElement,
  mapKey,
  mapValue,
  recordField,

  // Patterns.
  switchCase,
  switchArm,
  ifCase,

  // Operators and conditionals.
  equality,
  ternaryThen,
  ternaryElse,
  ifNull,

  // Constant contexts.
  paramDefault,
  constArg,
  annotationArg,

  // Assignment, and a context type that comes from an inferred type argument.
  assignment,
  typeArgument,

  // A shorthand inside this very file — no cross-library hop involved.
  sameFile,

  // Never used, in any form -> flagged.
  deadWeight,
}

/// The same-file shorthand: `Weight.sameFile` is reached from the library that
/// declares it, so no cross-library recovery is involved. Deliberately not a
/// `[Weight.sameFile]` doc link — that would be a reference of its own, and a
/// missed shorthand would surface as doc-only instead of unused.
Weight get sameFileWeight => .sameFile;

/// A shorthand resolves statics declared on an enum, not just its values.
enum Tier {
  // Referenced the long way below, so this one says nothing about shorthands.
  base;

  /// Reached only as `.standard`.
  static Tier get standard => Tier.base;

  /// Never used -> flagged.
  static Tier get deadStandard => Tier.base;
}

/// Static members and constructors reached only through a shorthand head.
class Palette {
  /// Reached only as `.new('…')`.
  Palette(this.name);

  /// Reached only as `.of('…')`.
  Palette.of(this.name);

  /// Never used -> flagged.
  Palette.deadCtor(this.name);

  // Builds the statics below, so it is referenced the ordinary way.
  const Palette._(this.name);

  final String name;

  /// Reached only as `.constField`.
  static const Palette constField = Palette._('const-field');

  /// Reached only as `.patternField`, in a constant pattern.
  static const Palette patternField = Palette._('pattern-field');

  /// Reached only as `.getter`.
  static Palette get getter => const Palette._('getter');

  /// Reached only as `.parse('…')`.
  static Palette parse(String source) => Palette._(source);

  /// Reached only as `.blend(…)`, with both arguments shorthands themselves.
  static Palette blend(Palette first, Palette second) =>
      Palette._('${first.name}+${second.name}');

  /// Reached only as `.tinted(…)`, whose argument is a *constructor* shorthand
  /// rather than a static one.
  static Palette tinted(Tint tint) => Palette._('tint-${tint.level}');

  /// Reached only as a nested shorthand inside `.blend(…)`.
  static const Palette nestedFirst = Palette._('nested-first');

  /// Reached only as a nested shorthand inside `.blend(…)`.
  static const Palette nestedSecond = Palette._('nested-second');

  /// Reached only as `.chainSeed`, followed by a further selector.
  static Palette get chainSeed => const Palette._('chain-seed');

  /// Reached only as `.cascadeSeed`, followed by a cascade.
  static Palette get cascadeSeed => const Palette._('cascade-seed');

  /// Never used -> flagged.
  static Palette get deadGetter => const Palette._('dead-getter');

  /// Never used -> flagged.
  static Palette deadParse(String source) => Palette._(source);

  Palette brightened() => Palette._('$name+bright');
}

// Nested constructor shorthands. `Layer`, `Depth`, and `Tint` form a chain
// constructed by a single `.new(.new(.new(…)))`: three unnamed heads in one
// expression, each a different class's constructor, and one link per nesting
// depth so a depth that goes unseen is a single finding.
//
// The nesting is also what makes the consumer never name `Depth` or `Tint`,
// which is the shape a references query actually trips over: it looks only in
// files that mention the constructor's class, and a shorthand mentions no class
// at all. `Layer` is spelled at the use site (a type annotation), so it stands
// as the control that does resolve.

/// The innermost link, and the only class here with a *named* constructor
/// reached by nesting.
class Tint {
  /// Reached only as the innermost `.new(…)` of `.new(.new(.new(…)))`.
  Tint(this.level);

  /// Reached only as the nested `.step(…)` in `.tinted(.step(…))`.
  Tint.step(this.level);

  /// Never used -> flagged: constructing a class through one shorthand must not
  /// exempt its other constructors.
  Tint.deadTint(this.level);

  final int level;
}

/// The middle link: nested inside a shorthand, with a shorthand nested in it.
class Depth {
  /// Reached only as the middle `.new(…)` of `.new(.new(.new(…)))`.
  Depth(this.tint);

  final Tint tint;
}

/// The outermost link.
class Layer {
  /// Reached only as the outer `.new(…)` of `.new(.new(.new(…)))`.
  Layer(this.depth);

  final Depth depth;
}

/// The control for the nested `.new` heads: the type is referenced, but no
/// shorthand ever constructs it.
class DeadLayer {
  /// Never used -> flagged.
  DeadLayer(this.depth);

  final Depth depth;
}

/// A generic static, whose type argument comes from the shorthand's context.
class Box<T> {
  const Box(this.value);

  final T value;

  /// Reached only as `.filled(…)`.
  static Box<T> filled<T>(T value) => Box(value);

  /// Never used -> flagged.
  static Box<T> deadFilled<T>(T value) => Box(value);
}

/// Gives the constant and annotation shorthands their context type.
class Marker {
  const Marker(this.weight);

  final Weight weight;
}
