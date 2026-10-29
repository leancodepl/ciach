/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the rules for the widget previews that `flutter widget-preview`
/// shows: the declarations whose annotation calls a constructor of Flutter's
/// `Preview` or `MultiPreview`, or of a subtype of either. As in
/// flutter_tools, an annotation that reads a constant doesn't count.
Iterable<EntryPoint> flutterWidgetPreviewEntryPoints(Pubspec pubspec) => [
  if (pubspec.dependencies.contains('flutter'))
    for (final annotation in const ['Preview', 'MultiPreview'])
      .annotatedWith(
        annotation,
        package: 'flutter',
        constants: false,
        reason: 'shown by `flutter widget-preview`',
      ),
];
