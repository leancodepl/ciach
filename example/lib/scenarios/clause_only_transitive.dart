// A type used only in the header of a mixin that `--remove` removes from
// its clauses.
// Scanned by its own test, with and without `transitive`.

/// Used only in the `implements` clause of `Painter` -> USED without transitive,
/// UNUSED with it.
abstract interface class Shape<T> {}

/// Used only in the `with` clause of `Tile` -> UNUSED (class), with the method.
mixin Painter implements Shape<int> {
  void paint() {}
}

class Tile with Painter {}

/// An entry point -> skipped; keeps `Tile` live.
@pragma('vm:entry-point')
Object tile() => Tile();
