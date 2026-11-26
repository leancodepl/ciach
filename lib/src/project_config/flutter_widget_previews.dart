/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/project_files.dart';

/// Returns the rules for the widget previews that `flutter widget-preview`
/// shows: the declarations whose annotation creates an object of Flutter's
/// `Preview` or `MultiPreview`, or of a subtype of either.
Iterable<EntryPoint> flutterWidgetPreviewEntryPoints(Pubspec pubspec) sync* {
  if (!pubspec.dependencies.contains('flutter')) {
    return;
  }
  for (final annotation in const ['Preview', 'MultiPreview']) {
    yield .annotationNamed(
      annotation,
      packages: const {'flutter'},
      matchesClass: true,
      reason: 'shown by `flutter widget-preview`',
    );
  }
}
