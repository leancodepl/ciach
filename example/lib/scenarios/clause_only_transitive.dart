// A type that only the header of a class removed from its clauses names.
// Scanned by its own test, with and without `transitive`.

/// Named only in `Painter`'s `implements` clause -> USED without transitive,
/// UNUSED with it.
abstract interface class Shape<T> {}

/// Named only in `Tile`'s `with` clause -> UNUSED (class), with the method.
mixin Painter implements Shape<int> {
  void paint() {}
}

class Tile with Painter {}

/// An entry point -> skipped; keeps `Tile` live.
@pragma('vm:entry-point')
Object tile() => Tile();
