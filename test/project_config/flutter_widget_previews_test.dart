/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/project_config/flutter_widget_previews.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';

void main() {
  final rules = EntryPoints(
    flutterWidgetPreviewEntryPoints((
      name: 'app',
      dependencies: {'flutter'},
      yaml: null,
    )).toList(),
  );

  /// Returns the reason of the rule that matches a function annotated with
  /// [annotationClass], in a package that depends on Flutter.
  String? reasonFor(AnnotationClass annotationClass) => rules
      .match(
        declarationAt(
          'lib/button.dart',
          symbol('buttonPreview'),
          null,
          annotationClasses: [annotationClass],
        ),
      )
      ?.reason;

  const object = ResolvedClass('Object', null);

  test(
    "keeps a declaration annotated with Flutter's `Preview` or `MultiPreview`, or a subtype of either",
    () {
      for (final annotationClass in [
        AnnotationClass(const .new('Preview', 'flutter'), {object}),
        AnnotationClass(const .new('DarkPreview', 'app'), {
          const .new('Preview', 'flutter'),
          object,
        }),
        AnnotationClass(const .new('ThemePreviews', 'app'), {
          const .new('MultiPreview', 'flutter'),
          object,
        }),
      ]) {
        expect(
          reasonFor(annotationClass),
          'shown by `flutter widget-preview`',
          reason: 'for $annotationClass',
        );
      }
    },
  );

  test('a `Preview` from another package is not a widget preview', () {
    for (final package in ['app', null]) {
      expect(
        reasonFor(.new(.new('Preview', package), {object})),
        isNull,
        reason: 'for $package',
      );
    }
  });

  test('a package that does not depend on Flutter has no preview rules', () {
    expect(
      flutterWidgetPreviewEntryPoints((
        name: 'app',
        dependencies: {'meta'},
        yaml: null,
      )),
      isEmpty,
    );
  });
}
