/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_class.dart';

import 'test_package.dart';

/// A new package for the tests of `ResolvedFiles`: `lib/previews.dart`
/// declares the classes, constants and type aliases that the annotations in
/// the tests name, and `lib/local.dart` declares a `JSExport` of its own.
TestPackage previewsPackage() => .new('resolved_files')
  ..writeAll({
    'pubspec.yaml': 'name: app\n',
    'lib/previews.dart': '''
class Preview {
  const Preview();
  const Preview.named();
}

class DarkPreview extends Preview {
  const DarkPreview();
}

mixin Themed {}

class ThemedPreview with Themed implements DarkPreview {
  const ThemedPreview();
}

const preview = Preview();

const sameAsPreview = preview;

const heldPreview = Holder.held;

const previewList = [Preview()];

class Typed<T> extends Preview {
  const Typed();
}

typedef AliasPreview = DarkPreview;

typedef AliasOfAlias = AliasPreview;

typedef AliasTyped<T extends Object> = Typed<T>;

class Holder {
  static const held = DarkPreview();
}
''',
    'lib/local.dart': '''
class JSExport {
  const JSExport();
}
''',
  });

const object = ResolvedClass('Object', 'dart:core');
ResolvedClass app(String name) => .new(name, 'app');
