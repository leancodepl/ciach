/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/report/annotations.dart';
import 'package:collection/collection.dart';
import 'package:xml/xml.dart';

/// A [Checkstyle][] XML report, which Jenkins (Warnings Next Generation),
/// SonarQube and most CI report plugins read: findings grouped by file, a
/// `warning` for each unused finding and empty file, an `info` for each
/// doc-only one.
///
/// [pathPrefix] is prepended to each path, as in `githubReport`.
///
/// [Checkstyle]: https://checkstyle.org
String checkstyleReport(FinderResult result, {String pathPrefix = '.'}) {
  final byFile = annotationsOf(
    result,
    pathPrefix,
  ).groupListsBy((annotation) => annotation.file);
  final builder = XmlBuilder()..declaration(encoding: 'UTF-8');
  builder.element(
    'checkstyle',
    attributes: {'version': '4.3'},
    nest: () {
      for (final MapEntry(key: file, value: annotations) in byFile.entries) {
        builder.element(
          'file',
          attributes: {'name': _xmlText(file)},
          nest: () {
            for (final (:check, file: _, :line, :column, :message)
                in annotations) {
              builder.element(
                'error',
                attributes: {
                  'line': ?line?.toString(),
                  'column': ?column?.toString(),
                  'severity': check.notice ? 'info' : 'warning',
                  'message': _xmlText(message),
                  'source': 'ciach.${check.id}',
                },
              );
            }
          },
        );
      }
    },
  );
  return '${builder.buildDocument().toXmlString(pretty: true, indent: '  ')}\n';
}

// XML 1.0 can't hold the other control characters, even as references.
String _xmlText(String value) =>
    value.replaceAll(RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');
