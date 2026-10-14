/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:convert';

import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/style.dart';
import 'package:ciach/src/version.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// What an empty file holds.
const _emptyFileContents =
    'nothing but comments and library, import or part-of directives';

/// Why `--remove` leaves an empty conditional-import variant.
const _emptyVariantNote =
    'a conditional-import variant: remove its `if` clause and the file by hand';

/// Renders a [FinderResult] for humans or machines.
abstract final class Reporter {
  /// The human-readable report: findings, extra sections, summary. Unless
  /// [verbose], each problem cause lists at most [maxListed] locations.
  static String text(
    FinderResult result, {
    Style style = .plain,
    bool verbose = false,
    int maxListed = 10,
  }) {
    final buffer = StringBuffer();
    _writeDeclarations(buffer, result.unused, style);

    final empty = result.allEmptyFiles;
    if (empty.isNotEmpty) {
      _writeHeading(
        buffer,
        'Empty files',
        empty.length,
        _emptyFileContents,
        style,
      );
      final variants = result.emptyVariants.toSet();
      for (final file in empty) {
        buffer.writeln(
          [
            style.path(file),
            if (variants.contains(file)) style.caution('($_emptyVariantNote)'),
          ].join('  '),
        );
      }
      buffer.writeln();
    }

    if (result.docOnly.isNotEmpty) {
      _writeHeading(
        buffer,
        'Referenced only from doc comments',
        result.docOnly.length,
        'not counted, never removed',
        style,
      );
      _writeDeclarations(buffer, result.docOnly, style);
    }

    if (result.recoveredReferences.isNotEmpty) {
      _writeHeading(
        buffer,
        'Recovered references',
        result.recoveredReferences.length,
        'missed by find-references; kept',
        style,
        caution: true,
      );
      _writeRecovered(buffer, result.recoveredReferences, style);
    }

    if (result.problems.isNotEmpty) {
      _writeHeading(
        buffer,
        'Not analyzed',
        result.problems.length,
        'the analysis failed here',
        style,
        caution: true,
      );
      _writeProblems(buffer, result.problems, style, verbose, maxListed);
    }

    buffer.write(_summary(result, style));
    return buffer.toString();
  }

  /// What `--remove` did; `null` [removal] means the user declined.
  static String removal(
    RemovalResult? removal, {
    int removed = 0,
    int blocked = 0,
    Iterable<String> notes = const [],
    Style style = .plain,
  }) {
    if (removal == null) {
      return style.note('Skipped removal.');
    }
    final files = removal.filesChanged;
    final deleted = removal.deletedFiles;
    final sentences = [
      if (removed > 0)
        style.success(
          'Removed ${plural(removed, 'unused declaration', 'unused declarations')} from '
          '${plural(files, 'file', 'files')}.',
        ),
      if (blocked > 0)
        style.caution('$blocked left in place — unsafe to auto-remove.'),
      if (removal.skipped case final skipped when skipped.isNotEmpty)
        style.caution(
          '${skipped.length} left in place — ciach could not tell how to cut ${skipped.length == 1 ? 'it' : 'them'} out: ${skipped.map((d) => '${d.name} (${d.filePath}:${d.line})').join(', ')}.',
        ),
      if (deleted.isNotEmpty)
        'Deleted ${plural(deleted.length, 'empty file', 'empty files')}: ${deleted.map((d) => d.filePath).join(', ')}.',
      style.note("Run 'dart format' to tidy up spacing."),
    ];
    final buffer = StringBuffer(sentences.join(' '));
    for (final note in notes) {
      buffer.write('\n${style.heading('Note:')} $note');
    }
    return buffer.toString();
  }

  /// A section heading.
  static void _writeHeading(
    StringBuffer buffer,
    String title,
    int count,
    String meaning,
    Style style, {
    bool caution = false,
  }) {
    final heading = style.heading('$title ($count)');
    buffer.writeln(
      '${caution ? style.caution(heading) : heading} ${style.note('· $meaning')}',
    );
  }

  /// Writes one file-grouped, aligned block of [decls] to [buffer].
  static void _writeDeclarations(
    StringBuffer buffer,
    List<UnusedDeclaration> decls,
    Style style,
  ) {
    for (final MapEntry(key: file, value: fileDecls)
        in decls.groupListsBy((d) => d.filePath).entries) {
      buffer.writeln(style.path(file));

      // Column widths for tidy alignment (each group is non-empty).
      final locWidth = fileDecls.map((d) => '${d.line}:${d.column}'.length).max;
      final kindWidth = fileDecls.map((d) => d.kind.label.length).max;

      for (final decl in fileDecls) {
        final loc = '${decl.line}:${decl.column}'.padRight(locWidth);
        final kind = decl.kind.label.padRight(kindWidth);
        final visibility = decl.isPrivate ? 'private' : 'public';
        final columns = [
          style.position(loc),
          style.kind(kind),
          decl.qualifiedName,
          style.note('($visibility)'),
          ..._notes(decl, style),
        ];
        buffer.writeln('  ${columns.join('  ')}');
      }
      buffer.writeln();
    }
  }

  static void _writeRecovered(
    StringBuffer buffer,
    List<RecoveredReference> recovered,
    Style style,
  ) {
    for (final MapEntry(key: file, value: inFile)
        in recovered.groupListsBy((r) => r.filePath).entries) {
      buffer.writeln(style.path(file));
      final locWidth = inFile.map((r) => '${r.line}:${r.column}'.length).max;
      for (final r in inFile) {
        final loc = '${r.line}:${r.column}'.padRight(locWidth);
        buffer.writeln(
          '  ${style.position(loc)}  ${r.qualifiedName}  '
          '${style.position('used at ${r.usageFilePath}:${r.usageLine}:${r.usageColumn}')}',
        );
      }
      buffer.writeln();
    }
  }

  /// [problems] grouped by summary, cause, then file.
  static void _writeProblems(
    StringBuffer buffer,
    List<AnalysisProblem> problems,
    Style style,
    bool verbose,
    int maxListed,
  ) {
    var hasDetail = false;
    for (final MapEntry(key: summary, value: ofSummary)
        in problems.groupListsBy((p) => p.summary).entries) {
      buffer.writeln('  $summary');
      for (final MapEntry(key: cause, value: ofCause)
          in ofSummary.groupListsBy((p) => p.cause).entries) {
        _writeCause(buffer, cause, ofCause, style, verbose, maxListed);
        hasDetail |= ofCause.first.detail != null;
      }
    }
    if (hasDetail && !verbose) {
      buffer.writeln(
        style.note('  Likely a Dart SDK bug; -v shows the stack traces.'),
      );
    }
    buffer.writeln();
  }

  static void _writeCause(
    StringBuffer buffer,
    String cause,
    List<AnalysisProblem> ofCause,
    Style style,
    bool verbose,
    int maxListed,
  ) {
    buffer.writeln('    ${style.failure(cause)}');
    final listed = verbose ? ofCause : ofCause.take(maxListed).toList();
    for (final MapEntry(key: file, value: inFile)
        in listed.groupListsBy((p) => p.filePath).entries) {
      buffer.writeln('    ${style.path(file)}');
      _writeProblemRows(buffer, inFile, style);
    }
    if (ofCause.length > listed.length) {
      buffer.writeln(
        style.note(
          '    … and ${ofCause.length - listed.length} more (-v lists them all)',
        ),
      );
    }
    if (ofCause.first.detail case final detail? when verbose) {
      buffer
        ..writeln(style.note('    Stack trace of the first:'))
        ..writeln(
          style.note(
            detail.split('\n').map((line) => '      $line').join('\n'),
          ),
        );
    }
  }

  static void _writeProblemRows(
    StringBuffer buffer,
    List<AnalysisProblem> inFile,
    Style style,
  ) {
    final rows = [
      for (final p in inFile)
        if (p.line != null) p,
    ];
    if (rows.isEmpty) {
      return;
    }
    final locWidth = rows.map((p) => '${p.line}:${p.column ?? 1}'.length).max;
    for (final p in rows) {
      final loc = '${p.line}:${p.column ?? 1}'.padRight(locWidth);
      buffer.writeln(
        '      ${style.position(loc)}${p.name?.let((name) => '  $name') ?? ''}',
      );
    }
  }

  /// What the text report adds in parentheses after a finding.
  static List<String> _notes(UnusedDeclaration decl, Style style) => [
    if (decl.removalBlocked)
      style.caution('(unsafe to auto-remove — remove manually)'),
    if (decl.hint case final hint?) style.note('($hint)'),
    if (_onlyReferencedFrom(decl) case final referrers?)
      style.note('($referrers)'),
  ];

  /// The first finding [decl] is only referenced from, and how many others
  /// there are; the JSON report lists them all.
  static String? _onlyReferencedFrom(UnusedDeclaration decl) {
    final referrers = decl.onlyReferencedFrom;
    if (referrers.isEmpty) {
      return null;
    }
    final (:qualifiedName, :filePath, :line) = referrers.first;
    final others = referrers.length > 1
        ? ' and ${referrers.length - 1} more'
        : '';
    return 'only referenced from dead $qualifiedName ($filePath:$line)$others';
  }

  /// A machine-readable JSON report.
  static String json(FinderResult result) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'summary': {
        'filesScanned': result.filesScanned,
        'declarationsChecked': result.declarationsChecked,
        'unusedCount': result.unused.length,
        'docOnlyCount': result.docOnly.length,
        'emptyFileCount': result.emptyFiles.length,
        'emptyVariantCount': result.emptyVariants.length,
        'elapsedMs': result.elapsed.inMilliseconds,
      },
      'unused': [for (final decl in result.unused) decl.toJson()],
      'docOnly': [for (final decl in result.docOnly) decl.toJson()],
      'emptyFiles': result.emptyFiles,
      'emptyVariants': result.emptyVariants,
      'warnings': [for (final w in result.recoveredReferences) w.toJson()],
      'problems': [for (final problem in result.problems) problem.toJson()],
    });
  }

  /// [GitHub Actions workflow commands][] — one `::warning` annotation per
  /// unused finding and empty file (surfacing them inline on the PR diff and
  /// Checks tab) and one lower-severity `::notice` per doc-only finding.
  ///
  /// Annotation paths are resolved relative to the repository root. [pathPrefix]
  /// (POSIX, `/`-separated) is prepended to each finding's path so that scans of
  /// a sub-directory still point at the right file; it defaults to `.` (the
  /// scan root is the repository root).
  ///
  /// [GitHub Actions workflow commands]: https://docs.github.com/actions/reference/workflow-commands-for-github-actions
  static String github(FinderResult result, {String pathPrefix = '.'}) {
    final buffer = StringBuffer();
    for (final (:check, :file, :line, :column, :message) in _annotations(
      result,
      pathPrefix,
    )) {
      final properties = [
        'file=${_escapeProperty(file)}',
        ?line?.let((line) => 'line=$line'),
        ?column?.let((column) => 'col=$column'),
        'title=${_escapeProperty(check.title)}',
      ];
      buffer.writeln(
        "::${check.notice ? 'notice' : 'warning'} ${properties.join(',')}::${_escapeData(message)}",
      );
    }
    return buffer.toString();
  }

  /// [Azure Pipelines logging commands][] — one `task.logissue` warning per
  /// finding, which the run's summary lists with its file and line. Azure has
  /// no severity below a warning, so doc-only findings are warnings too.
  ///
  /// [pathPrefix] is prepended to each path, as in [github].
  ///
  /// [Azure Pipelines logging commands]: https://learn.microsoft.com/azure/devops/pipelines/scripts/logging-commands
  static String azure(FinderResult result, {String pathPrefix = '.'}) {
    final buffer = StringBuffer();
    for (final (:check, :file, :line, :column, :message) in _annotations(
      result,
      pathPrefix,
    )) {
      final properties = [
        'type=warning',
        'sourcepath=${_escapeAzure(file, property: true)}',
        ?line?.let((line) => 'linenumber=$line'),
        ?column?.let((column) => 'columnnumber=$column'),
      ];
      buffer.writeln(
        "##vso[task.logissue ${properties.join(';')}]${_escapeAzure('${check.title}: $message')}",
      );
    }
    return buffer.toString();
  }

  /// [TeamCity inspections][] — one `inspection` service message per finding,
  /// which the build's Inspections tab groups by type: a `WARNING` for each
  /// unused finding and empty file, a `WEAK WARNING` for each doc-only one.
  /// Each type is declared by an `inspectionType` message before its first
  /// use.
  ///
  /// [pathPrefix] is prepended to each path, as in [github].
  ///
  /// [TeamCity inspections]: https://www.jetbrains.com/help/teamcity/service-messages.html#Reporting+Inspections
  static String teamCity(FinderResult result, {String pathPrefix = '.'}) {
    final buffer = StringBuffer();
    final declared = <_Check>{};
    for (final (:check, :file, :line, column: _, :message) in _annotations(
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

  /// A [SARIF 2.1.0][] log, which GitHub code scanning, Azure DevOps and most
  /// static-analysis dashboards import: one result per finding, a `warning`
  /// for each unused finding and empty file, a `note` for each doc-only one.
  ///
  /// [pathPrefix] is prepended to each path, as in [github].
  ///
  /// [SARIF 2.1.0]: https://docs.oasis-open.org/sarif/sarif/v2.1.0/sarif-v2.1.0.html
  static String sarif(FinderResult result, {String pathPrefix = '.'}) {
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
                for (final check in _Check.values)
                  {
                    'id': check.id,
                    'shortDescription': {'text': check.title},
                  },
              ],
            },
          },
          'results': [
            for (final (:check, :file, :line, :column, :message)
                in _annotations(result, pathPrefix))
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

  /// A [Checkstyle][] XML report, which Jenkins (Warnings Next Generation),
  /// SonarQube and most CI report plugins read: findings grouped by file, a
  /// `warning` for each unused finding and empty file, an `info` for each
  /// doc-only one.
  ///
  /// [pathPrefix] is prepended to each path, as in [github].
  ///
  /// [Checkstyle]: https://checkstyle.org
  static String checkstyle(FinderResult result, {String pathPrefix = '.'}) {
    final byFile = _annotations(
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

  /// A [GitLab Code Quality][] report, for a job's `codequality` artifact,
  /// which GitLab shows on the merge request: a `minor` issue for each unused
  /// finding and empty file, an `info` one for each doc-only one. Each
  /// fingerprint hashes the finding without its line, so a finding that only
  /// moved is not reported as new.
  ///
  /// [pathPrefix] is prepended to each path, as in [github].
  ///
  /// [GitLab Code Quality]: https://docs.gitlab.com/ci/testing/code_quality/#code-quality-report-format
  static String gitlab(FinderResult result, {String pathPrefix = '.'}) {
    const encoder = JsonEncoder.withIndent('  ');
    final seen = <String, int>{};
    final issues = <Map<String, Object?>>[];
    for (final (:check, :file, :line, column: _, :message) in _annotations(
      result,
      pathPrefix,
    )) {
      final key = [check.id, file, message].join('\n');
      // The occurrence tells identical findings in one file apart.
      final occurrence = seen.update(key, (n) => n + 1, ifAbsent: () => 0);
      issues.add({
        'description': message,
        'check_name': check.id,
        'fingerprint': _fingerprint('$key\n$occurrence'),
        'severity': check.notice ? 'info' : 'minor',
        'location': {
          'path': file,
          'lines': {'begin': line ?? 1},
        },
      });
    }
    return encoder.convert(issues);
  }

  /// A 64-bit FNV-1a hash of [key], in hex.
  static String _fingerprint(String key) {
    // ciach runs on the VM only, where an int holds the whole offset.
    // ignore: avoid_js_rounded_ints
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(key)) {
      hash = (hash ^ byte) * 0x100000001b3;
    }
    // Unsigned, in halves: a 64-bit int with the top bit set is negative.
    return [
      hash >>> 32,
      hash & 0xffffffff,
    ].map((half) => half.toRadixString(16).padLeft(8, '0')).join();
  }

  /// Every finding of [result] as an annotation, its path prefixed with
  /// [pathPrefix]: unused declarations, empty files, doc-only findings,
  /// recovered references and problems, in that order.
  static Iterable<_Annotation> _annotations(
    FinderResult result,
    String pathPrefix,
  ) sync* {
    String file(String filePath) => _annotationFile(filePath, pathPrefix);
    for (final decl in result.unused) {
      yield (
        check: .unused,
        file: file(decl.filePath),
        line: decl.line,
        column: decl.column,
        message: [
          "Unused ${decl.isPrivate ? 'private ' : ''}${decl.kind.label} '${decl.qualifiedName}'",
          ?decl.hint,
          ?_onlyReferencedFrom(decl),
        ].join(' — '),
      );
    }
    final variants = result.emptyVariants.toSet();
    for (final emptyFile in result.allEmptyFiles) {
      yield (
        check: .emptyFile,
        file: file(emptyFile),
        line: 1,
        column: 1,
        message: [
          'Has $_emptyFileContents',
          if (variants.contains(emptyFile)) _emptyVariantNote,
        ].join(' — '),
      );
    }
    for (final decl in result.docOnly) {
      yield (
        check: .docOnly,
        file: file(decl.filePath),
        line: decl.line,
        column: decl.column,
        message:
            "${decl.kind.label} '${decl.qualifiedName}' has no code references, only a dartdoc link",
      );
    }
    for (final w in result.recoveredReferences) {
      yield (
        check: .recovered,
        file: file(w.filePath),
        line: w.line,
        column: w.column,
        message: "'${w.qualifiedName}' ${w.message}",
      );
    }
    for (final problem in result.problems) {
      final name = problem.name?.let((name) => "'$name': ") ?? '';
      yield (
        check: .notAnalyzed,
        file: file(problem.filePath),
        line: problem.line,
        column: problem.column,
        message: '$name${problem.summary} Cause: ${problem.cause}',
      );
    }
  }

  static String _annotationFile(String filePath, String pathPrefix) =>
      pathPrefix == '.' || pathPrefix.isEmpty
      ? filePath
      : p.posix.normalize('$pathPrefix/$filePath');

  // Escaping per the workflow-command spec.
  static String _escapeData(String value) => value
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');

  static String _escapeProperty(String value) =>
      _escapeData(value).replaceAll(':', '%3A').replaceAll(',', '%2C');

  // XML 1.0 can't hold the other control characters, even as references.
  static String _xmlText(String value) =>
      value.replaceAll(RegExp('[\x00-\x08\x0B\x0C\x0E-\x1F]'), '');

  // Escaping per the Azure Pipelines agent, which unescapes `%AZP25` last.
  static String _escapeAzure(String value, {bool property = false}) {
    final data = value
        .replaceAll('%', '%AZP25')
        .replaceAll('\r', '%0D')
        .replaceAll('\n', '%0A');
    return property ? data.replaceAll(';', '%3B').replaceAll(']', '%5D') : data;
  }

  static void _writeTeamCity(
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
  static String _escapeTeamCity(String value) => value
      .replaceAll('|', '||')
      .replaceAll("'", "|'")
      .replaceAll('\n', '|n')
      .replaceAll('\r', '|r')
      .replaceAll('[', '|[')
      .replaceAll(']', '|]')
      .replaceAll('\u0085', '|x')
      .replaceAll('\u2028', '|l')
      .replaceAll('\u2029', '|p');

  static String _summary(FinderResult result, Style style) {
    final count = result.unused.length;
    final fileCount = result.unused.map((d) => d.filePath).toSet().length;
    final seconds = (result.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final headline = count == 0
        ? style.success('No unused declarations found')
        : style.attention(
            'Found ${plural(count, 'unused declaration', 'unused declarations')} in '
            '${plural(fileCount, 'file', 'files')}',
          );
    final scanned = style.note(
      '(scanned ${plural(result.filesScanned, 'file', 'files')}, '
      '${plural(result.declarationsChecked, 'declaration', 'declarations')}, ${seconds}s)',
    );
    final sections = [
      if (result.allEmptyFiles.isNotEmpty)
        style.attention(
          plural(result.allEmptyFiles.length, 'empty file', 'empty files'),
        ),
      if (result.docOnly.isNotEmpty) '${result.docOnly.length} doc-only',
      if (result.recoveredReferences.isNotEmpty)
        style.caution('${result.recoveredReferences.length} recovered'),
      if (result.problems.isNotEmpty)
        style.caution('${result.problems.length} not analyzed'),
    ];
    return ['$headline $scanned', ...sections].join(style.note(' · '));
  }
}

/// What kind of finding an annotation is: its id and title, as the CI
/// services group and label it, and whether it is below a warning.
enum _Check {
  unused('unused-declaration', 'Unused declaration'),
  emptyFile('empty-file', 'Empty file'),
  docOnly('doc-only', 'Referenced only from a doc comment', notice: true),
  recovered(
    'recovered-reference',
    'Recovered reference (possible analyzer bug)',
  ),
  notAnalyzed('not-analyzed', 'Could not analyze');

  const _Check(this.id, this.title, {this.notice = false});

  final String id;
  final String title;
  final bool notice;
}

/// One finding, where it is, and what to say about it.
typedef _Annotation = ({
  _Check check,
  String file,
  int? line,
  int? column,
  String message,
});
