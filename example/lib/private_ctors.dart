// Fixtures for private constructors. They are NOT special-cased: an unused
// private constructor is reported (and removable) like any other dead code.
// A sole, zero-parameter `Foo._()` additionally carries a prevent-instantiation
// hint nudging toward `abstract final class`.
// Expected "unused" set is asserted by test/finder_test.dart — keep in sync.

/// Sole, zero-parameter private constructor: the classic prevent-instantiation
/// shape. It is never referenced, so it IS reported as unused — and carries the
/// `abstract final class` hint. The class is kept alive by `SoleMarker.tag`.
class SoleMarker {
  SoleMarker._();

  /// Referenced from bin/app.dart -> USED (also keeps the class alive).
  static const tag = 'sole';
}

/// Two private constructors. The never-used `_unused` is dead and IS reported;
/// because the class has more than one constructor it is not the
/// prevent-instantiation shape, so it gets no hint. `_used` is hit by
/// [describe].
class MultiCtor {
  MultiCtor._used();

  MultiCtor._unused();

  /// Referenced from bin/app.dart -> USED; also marks `_used` referenced.
  static String describe() => MultiCtor._used().toString();
}

/// Sole private constructor, but with parameters — dead and reported, but not
/// the zero-parameter prevent-instantiation shape, so it gets no hint. Kept
/// alive by the `ParamCtor.tag` reference.
class ParamCtor {
  ParamCtor._(int value) {
    print(value);
  }

  /// Referenced from bin/app.dart -> USED (also keeps the class alive).
  static const tag = 'param';
}
