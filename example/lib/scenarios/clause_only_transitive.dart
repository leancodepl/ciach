// A type used only in the header of a mixin that `--remove` removes from
// its clauses.
// Scanned by its own test, with and without `transitive`.

/// Used only in the bound of `Painter`'s type parameter -> USED without
/// transitive, UNUSED with it.
abstract interface class Shape {}

/// Used only in the `with` clause of `Tile` -> UNUSED (class), reported
/// without its method.
mixin Painter<T extends Shape> {
  void paint() {}
}

/// Used only as the type argument of `Labeled` in `Tile` -> USED without
/// transitive, UNUSED with it.
abstract interface class Label {}

/// Used only in the `implements` clause of `Tile` -> UNUSED (class).
abstract interface class Labeled<T> {}

class Tile with Painter implements Labeled<Label> {}

/// An entry point -> skipped; keeps `Tile` live.
@pragma('vm:entry-point')
Object tile() => Tile();
