// Fixtures for the narrowed private-constructor rule.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Sole, zero-parameter private constructor: the classic prevent-instantiation
/// marker. The constructor is intentionally never referenced, so it is skipped
/// rather than reported. The class itself is kept alive by the `SoleMarker.tag`
/// static reference in bin/app.dart.
class SoleMarker {
  SoleMarker._();

  /// Referenced from bin/app.dart -> USED (also keeps the class alive).
  static const tag = 'sole';
}

/// A class with two private constructors. `_used` is referenced by [describe];
/// `_unused` is never referenced. Because the class declares more than one
/// constructor, `_unused` is genuinely dead and IS reported.
class MultiCtor {
  MultiCtor._used();

  MultiCtor._unused();

  /// Referenced from bin/app.dart -> USED. Keeps the class alive and marks
  /// `_used` as referenced.
  static String describe() => MultiCtor._used().toString();
}

/// A class whose sole constructor is private but takes parameters. The
/// parameters mean it is not the bare prevent-instantiation marker, so — being
/// never referenced — it IS reported. The class is kept alive by the
/// `ParamCtor.tag` static reference in bin/app.dart.
class ParamCtor {
  ParamCtor._(int value) {
    print(value);
  }

  /// Referenced from bin/app.dart -> USED (also keeps the class alive).
  static const tag = 'param';
}
