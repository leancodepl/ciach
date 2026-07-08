// An enum, a mixin, and an abstract class with an override.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Compass directions -> demonstrates enum values.
enum Direction {
  /// Referenced from bin/app.dart -> USED.
  north,

  /// Never referenced anywhere -> UNUSED (enum value).
  south,

  /// Referenced inside [Dog.pace] -> USED.
  east,

  /// Never referenced anywhere -> UNUSED (enum value).
  west,
}

/// Adds shared bark-shaping helpers -> demonstrates a mixin.
mixin Loud {
  /// Used by the mixed-in Dog.sound implementation -> USED.
  String emphasize(String text) => '$text!!!';

  /// Never referenced -> UNUSED (mixin method).
  String whisper(String text) => text.toLowerCase();
}

abstract class Animal {
  /// Never called anywhere -> UNUSED (public method), even though the class is
  /// instantiated.
  String sound();
}

class Dog extends Animal with Loud {
  // An @override whose interface method is never called. The finder skips it by
  // default; with --overrides it should be reported as unused too.
  @override
  String sound() => emphasize('woof');

  /// Referenced from bin/app.dart -> USED.
  void pace(Direction to) {
    if (to == Direction.east) {
      print('trotting east');
    }
  }
}
