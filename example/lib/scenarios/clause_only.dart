// Classes and mixins whose members are all dead and that only `with` or
// `implements` clauses name: `--remove` drops them with those clause entries.
// Scanned by its own test.

/// Named only in `with` clauses, its one member dead -> UNUSED (class),
/// with the method.
mixin Painter {
  void paint() {}
}

/// Named only in an `implements` clause -> UNUSED (class), with the method
/// and its override in `Canvas`.
abstract class Drawable {
  void draw();
}

/// No members, named only in a `with` clause -> UNUSED (class).
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

/// Reached from nothing -> UNUSED (function).
int useClauses(Object any) {
  Canvas();
  Brushed().brush();
  Checker();
  Picture();
  Held();
  return Easel().tidy() + (any is Checked ? 1 : 0);
}
