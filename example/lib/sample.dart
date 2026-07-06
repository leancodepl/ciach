// A fixture library with a deliberate mix of used and unused declarations.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Referenced from bin/app.dart -> USED.
void registerHandlers() {
  _internalHelper();
}

/// Referenced only by [registerHandlers] -> USED.
void _internalHelper() {}

/// Never referenced anywhere -> UNUSED (public function).
void danglingFunction() {}

/// Never referenced anywhere -> UNUSED (private function).
void _danglingPrivate() {}

/// Referenced from bin/app.dart -> USED.
const usedConstant = 'hello';

/// Never referenced anywhere -> UNUSED (public constant).
const unusedConstant = 'bye';

class UsedClass {
  /// Referenced from bin/app.dart -> USED.
  UsedClass(this.name);

  /// Never referenced -> UNUSED. Reported as `UsedClass.named`, not
  /// `UsedClass.UsedClass.named`.
  UsedClass.named(this.name);

  /// Referenced inside [_format] -> USED.
  final String name;

  /// Referenced from bin/app.dart -> USED.
  void greet() => _format();

  /// Referenced by [greet] -> USED.
  String _format() => 'Hi, $name';

  /// Never referenced -> UNUSED (public method).
  void unusedMethod() {}

  /// Never referenced -> UNUSED (private field).
  final int _unusedField = 0;
}

/// Never referenced anywhere -> UNUSED (class).
class UnusedClass {
  /// Method of an unused class; also never referenced -> UNUSED.
  void orphanMethod() {}
}

/// Never instantiated, so its unnamed constructor is UNUSED and reported as
/// `Unconstructed.new`. The class itself is not reported: the analysis server
/// treats the explicit constructor's declaration as a use of the class name.
class Unconstructed {
  Unconstructed();
}

abstract class Animal {
  /// Never called anywhere -> UNUSED (public method), even though the class is
  /// instantiated.
  String sound();
}

class Dog extends Animal {
  // An @override whose interface method is never called. The finder skips it by
  // default; with --overrides it should be reported as unused too.
  @override
  String sound() => 'woof';
}
