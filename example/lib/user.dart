// A class exercising constructors, fields, methods, and properties.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

class UsedClass {
  /// Referenced from bin/app.dart -> USED.
  UsedClass(this.name);

  /// Never referenced -> UNUSED. Reported as `UsedClass.named`, not
  /// `UsedClass.UsedClass.named`.
  UsedClass.named(this.name);

  /// Referenced inside [_format] and [nickname] -> USED.
  final String name;

  /// Backs [nickname]; referenced by its getter and setter -> USED.
  String _nickname = '';

  /// Referenced from bin/app.dart -> USED (property getter).
  String get nickname => _nickname.isEmpty ? name : _nickname;

  /// Referenced from bin/app.dart -> USED (property setter).
  set nickname(String value) => _nickname = value;

  /// Never referenced -> UNUSED (property getter).
  String get shout => '${name.toUpperCase()}!';

  /// Referenced from bin/app.dart -> USED.
  void greet() => _format();

  /// Referenced by [greet] -> USED.
  String _format() => 'Hi, $name';

  /// Never referenced -> UNUSED (public method).
  void unusedMethod() {}

  /// Never referenced -> UNUSED (private field).
  final int _unusedField = 0;
}
