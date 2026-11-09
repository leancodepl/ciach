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
      buffer.writeln(
        _serviceMessage('inspectionType', [
          ('id', typeId),
          ('name', check.title),
          ('category', 'ciach'),
          ('description', check.title),
        ]),
      );
    }
    buffer.writeln(
      _serviceMessage('inspection', [
        ('typeId', typeId),
        ('message', message),
        ('file', file),
        ?line?.let((line) => ('line', '$line')),
        ('SEVERITY', check.notice ? 'WEAK WARNING' : 'WARNING'),
      ]),
    );
  }
  return buffer.toString();
}

String _serviceMessage(String name, List<(String, String)> attributes) {
  final rendered = [
    for (final (key, value) in attributes) "$key='${_escapeTeamCity(value)}'",
  ];
  return '##teamcity[$name ${rendered.join(' ')}]';
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
