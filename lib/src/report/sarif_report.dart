/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:convert';

import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/report/annotations.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/version.dart';

/// A [SARIF 2.1.0][] log, which GitHub code scanning, Azure DevOps and most
/// static-analysis dashboards import: one result per finding, a `warning`
/// for each unused finding and empty file, a `note` for each doc-only one.
///
/// [pathPrefix] is prepended to each path, as in `githubReport`.
///
/// [SARIF 2.1.0]: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
String sarifReport(FinderResult result, {String pathPrefix = '.'}) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert({
    r'$schema': 'https://json.schemastore.org/sarif-2.1.0.json',
    'version': '2.1.0',
    'runs': [
      {
        'tool': {
          'driver': {
            'name': 'ciach',
            'version': ciachVersion,
            'informationUri': 'https://github.com/leancodepl/ciach',
            'rules': [
              for (final check in Check.values)
                {
                  'id': check.id,
                  'shortDescription': {'text': check.title},
                },
            ],
          },
        },
        'results': [
          for (final (:check, :file, :line, :column, :message) in annotationsOf(
            result,
            pathPrefix,
          ))
            {
              'ruleId': check.id,
              'ruleIndex': check.index,
              'level': check.notice ? 'note' : 'warning',
              'message': {'text': message},
              'locations': [
                {
                  'physicalLocation': {
                    'artifactLocation': {'uri': Uri(path: file).toString()},
                    'region': ?line?.let(
                      (line) => {'startLine': line, 'startColumn': ?column},
                    ),
                  },
                },
              ],
            },
        ],
      },
    ],
  });
}
