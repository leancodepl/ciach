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
import 'package:ciach/src/util/extensions.dart';

/// [TeamCity inspections][] — one `inspection` service message per finding,
/// which the build's Inspections tab groups by type: a `WARNING` for each
/// unused finding and empty file, a `WEAK WARNING` for each doc-only one.
/// Each type is declared by an `inspectionType` message before its first
/// use.
///
/// [pathPrefix] is prepended to each path, as in `githubReport`.
///
/// [TeamCity inspections]: https://www.jetbrains.com/help/teamcity/service-messages.html#Reporting+Inspections
String teamCityReport(FinderResult result, {String pathPrefix = '.'}) {
  final buffer = StringBuffer();
  final declared = <Check>{};
  for (final (:check, :file, :line, column: _, :message) in annotationsOf(
    result,
    pathPrefix,
  )) {
    final typeId = 'ciach.${check.id}';
    if (declared.add(check)) {
      _writeTeamCity(buffer, 'inspectionType', [
        ('id', typeId),
        ('name', check.title),
        ('category', 'ciach'),
        ('description', check.title),
      ]);
    }
    _writeTeamCity(buffer, 'inspection', [
      ('typeId', typeId),
      ('message', message),
      ('file', file),
      ?line?.let((line) => ('line', '$line')),
      ('SEVERITY', check.notice ? 'WEAK WARNING' : 'WARNING'),
    ]);
  }
  return buffer.toString();
}

void _writeTeamCity(
  StringBuffer buffer,
  String name,
  List<(String, String)> attributes,
) {
  final rendered = [
    for (final (key, value) in attributes) "$key='${_escapeTeamCity(value)}'",
  ];
  buffer.writeln('##teamcity[$name ${rendered.join(' ')}]');
}

// Escaping per the service-message spec; `|` goes first.
String _escapeTeamCity(String value) => value
    .replaceAll('|', '||')
    .replaceAll("'", "|'")
    .replaceAll('\n', '|n')
    .replaceAll('\r', '|r')
    .replaceAll('[', '|[')
    .replaceAll(']', '|]')
    .replaceAll('\u0085', '|x')
    .replaceAll('\u2028', '|l')
    .replaceAll('\u2029', '|p');
