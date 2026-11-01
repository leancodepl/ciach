/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/lsp/hover_text.dart';
import 'package:test/test.dart';

void main() {
  group('declaringPackageIn', () {
    test('returns the SDK library that declares a constructor', () {
      expect(
        declaringPackageIn('''
```dart
pragma(String name, [Object? options])
```
Declared in `pragma` in *dart:core*.
'''),
        'dart:core',
      );
    });

    test('returns the SDK library that declares a class', () {
      expect(
        declaringPackageIn('''
```dart
class JSExport
```
Declared in *dart:js_interop*.
---
Annotation to allow Dart classes to be wrapped with a JS object.
'''),
        'dart:js_interop',
      );
    });

    test('reads the library that Dart 3.10 writes between underscores', () {
      expect(
        declaringPackageIn('Declared in `JSExport` in _dart:_js_annotations_.'),
        'dart:_js_annotations',
      );
    });

    test('returns the package of a `package:` library', () {
      expect(
        declaringPackageIn(
          'Declared in *package:test_reflective_loader/test_reflective_loader.dart*.',
        ),
        'test_reflective_loader',
      );
    });

    test('returns `null` for a hover without a "Declared in" line', () {
      expect(
        declaringPackageIn('''
```dart
int x
```
'''),
        isNull,
      );
    });

    test('returns `null` for a library outside any package', () {
      expect(declaringPackageIn('Declared in *file:///a/b.dart*.'), isNull);
    });
  });
}
