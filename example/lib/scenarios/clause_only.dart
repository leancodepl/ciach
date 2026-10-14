// Classes and mixins whose members are all unused and that only `with` or
// `implements` clauses use. `--remove` removes them and their clause entries.
// Scanned by its own test.

/// Used only in `with` clauses, and its one member is unused -> UNUSED
/// (class), reported without its method.
mixin Painter {
  void paint() {}
}

/// Used only in an `implements` clause -> UNUSED (class), reported without
/// its method. `--remove` also deletes the override in `Canvas`.
abstract class Drawable {
  void draw();
}

/// Has no members and is used only in a `with` clause -> UNUSED (class).
mixin Plain {}

/// Called through `Easel` -> USED.
mixin Tidy {
  int tidy() => 0;
}

class Canvas with Painter implements Drawable {
  @override
  void draw() {}
}

class Easel extends Object with Tidy, Painter, Plain {}

/// Tested with `is` -> stays; only its method is reported.
mixin Checked {
  void check() {}
}

class Checker with Checked {}

/// The `on` type of `Brush` -> stays; only its method is reported.
mixin Primed {
  void prime() {}
}

/// Called through `Brushed` -> USED.
mixin Brush on Primed {
  void brush() {}
}

class Brushed with Primed, Brush {}

/// Extended -> stays; only its method is reported.
class Frame {
  void frame() {}
}

class Picture extends Frame {}

/// Generic -> stays; only its method is reported.
mixin Holder<T> {
  void hold() {}
}

class Held with Holder<int> {}

/// Used only in the `with` clause of a class without a body -> UNUSED
/// (class), reported without its method.
mixin Sketch {
  void sketch() {}
}

class Sketched(final int size) with Sketch;

/// Used in the `with` clause of a mixin application class that has another
/// mixin -> UNUSED (class), reported without its method.
mixin Glazed {
  void glaze() {}
}

/// Called through `Varnished` -> USED.
mixin Varnish {
  int varnish() => 0;
}

class Varnished = Object with Glazed, Varnish;

/// A mixin application class's only mixin -> stays; only its method is
/// reported.
mixin Lacquer {
  void lacquer() {}
}

class Lacquered = Object with Lacquer;

/// Reached from nothing -> UNUSED (function).
int useClauses(Object any) {
  Canvas();
  Brushed().brush();
  Checker();
  Picture();
  Held();
  const Lacquered();
  return Easel().tidy() +
      const Varnished().varnish() +
      Sketched(1).size +
      (any is Checked ? 1 : 0);
}
