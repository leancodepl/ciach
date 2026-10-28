/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/flutter_widget_previews.dart';
import 'package:pro_lsp/pro_lsp.dart';
import 'package:test/test.dart';

void main() {
  final flutter = Uri.parse(
    'package:flutter/src/widget_previews/widget_previews.dart',
  );
  final app = Uri.parse('package:app/previews.dart');
  const range = Range(
    start: .new(line: 0, character: 0),
    end: .new(line: 0, character: 0),
  );
  const buttonPreview = DocumentSymbol(
    name: 'buttonPreview',
    kind: .function,
    range: range,
    selectionRange: range,
  );

  /// Returns the reason of the rule that matches a function whose annotation
  /// has the classes [types], in a package that depends on Flutter.
  String? reasonFor(Set<AnnotationClass> types) =>
      EntryPoints(
            flutterWidgetPreviewEntryPoints((
              name: 'app',
              dependencies: {'flutter'},
              yaml: null,
            )).toList(),
          )
          .match('lib/button.dart', buttonPreview, null, annotationTypes: types)
          ?.reason;

  test(
    "keeps a declaration annotated with Flutter's `Preview` or `MultiPreview`, or a subclass of either",
    () {
      for (final types in [
        {AnnotationClass('Preview', flutter)},
        {
          AnnotationClass('DarkPreview', app),
          AnnotationClass('Preview', flutter),
        },
        {
          AnnotationClass('ThemePreviews', app),
          AnnotationClass('MultiPreview', flutter),
        },
      ]) {
        expect(
          reasonFor(types),
          'shown by `flutter widget-preview`',
          reason: 'for $types',
        );
      }
    },
  );

  test('a `Preview` from another library is not a widget preview', () {
    expect(reasonFor({.new('Preview', app)}), isNull);
    expect(reasonFor({const .new('Preview', null)}), isNull);
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
