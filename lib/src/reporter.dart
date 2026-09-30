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

import 'package:ciach/src/models.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/style.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

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
    final buffer = StringBuffer(
      style.success(
        'Removed ${plural(removed, 'unused declaration')} from '
        '${plural(files, 'file')}.',
      ),
    );
    if (blocked > 0) {
      buffer.write(
        ' ${style.caution('$blocked left in place — unsafe to auto-remove.')}',
      );
    }
    if (deleted.isNotEmpty) {
      buffer.write(
        ' Deleted ${plural(deleted.length, 'now-empty file')}: '
        '${deleted.map((d) => d.filePath).join(', ')}.',
      );
    }
    buffer.write(" ${style.note("Run 'dart format' to tidy up spacing.")}");
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
          '${style.position('used at ${r.usageFilePath}:${r.usageLine}:'
          '${r.usageColumn}')}',
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
        buffer.writeln('    ${style.failure(cause)}');
        final listed = verbose ? ofCause : ofCause.take(maxListed).toList();
        for (final MapEntry(key: file, value: inFile)
            in listed.groupListsBy((p) => p.filePath).entries) {
          buffer.writeln('    ${style.path(file)}');
          final rows = [
            for (final p in inFile)
              if (p.line != null) p,
          ];
          if (rows.isEmpty) {
            continue;
          }
          final locWidth = rows
              .map((p) => '${p.line}:${p.column ?? 1}'.length)
              .max;
          for (final p in rows) {
            final loc = '${p.line}:${p.column ?? 1}'.padRight(locWidth);
            buffer.writeln(
              '      ${style.position(loc)}${p.name == null ? '' : '  ${p.name}'}',
            );
          }
        }
        if (ofCause.length > listed.length) {
          buffer.writeln(
            style.note(
              '    … and ${ofCause.length - listed.length} more '
              '(-v lists them all)',
            ),
          );
        }
        final detail = ofCause.first.detail;
        hasDetail |= detail != null;
        if (verbose && detail != null) {
          buffer
            ..writeln(style.note('    Stack trace of the first:'))
            ..writeln(
              style.note(
                detail.split('\n').map((line) => '      $line').join('\n'),
              ),
            );
        }
      }
    }
    if (hasDetail && !verbose) {
      buffer.writeln(
        style.note('  Likely a Dart SDK bug; -v shows the stack traces.'),
      );
    }
    buffer.writeln();
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
        'elapsedMs': result.elapsed.inMilliseconds,
      },
      'unused': [for (final decl in result.unused) decl.toJson()],
      'docOnly': [for (final decl in result.docOnly) decl.toJson()],
      'warnings': [for (final w in result.recoveredReferences) w.toJson()],
      'problems': [for (final problem in result.problems) problem.toJson()],
    });
  }

  /// [GitHub Actions workflow commands][] — one `::warning` annotation per
  /// unused finding (surfacing them inline on the PR diff and Checks tab) and
  /// one lower-severity `::notice` per doc-only finding.
  ///
  /// Annotation paths are resolved relative to the repository root. [pathPrefix]
  /// (POSIX, `/`-separated) is prepended to each finding's path so that scans of
  /// a sub-directory still point at the right file; it defaults to `.` (the
  /// scan root is the repository root).
  ///
  /// [GitHub Actions workflow commands]: https://docs.github.com/actions/reference/workflow-commands-for-github-actions
  static String github(FinderResult result, {String pathPrefix = '.'}) {
    final buffer = StringBuffer();
    for (final decl in result.unused) {
      _writeAnnotation(
        buffer,
        decl,
        pathPrefix,
        level: 'warning',
        title: 'Unused declaration',
        message: [
          "Unused ${decl.isPrivate ? 'private ' : ''}${decl.kind.label} '${decl.qualifiedName}'",
          ?decl.hint,
          ?_onlyReferencedFrom(decl),
        ].join(' — '),
      );
    }
    for (final decl in result.docOnly) {
      _writeAnnotation(
        buffer,
        decl,
        pathPrefix,
        level: 'notice',
        title: 'Referenced only from a doc comment',
        message:
            "${decl.kind.label} '${decl.qualifiedName}' has no code "
            'references, only a dartdoc link',
      );
    }
    for (final w in result.recoveredReferences) {
      _writeAnnotationRaw(
        buffer,
        _annotationFile(w.filePath, pathPrefix),
        w.line,
        w.column,
        level: 'warning',
        title: 'Recovered reference (possible analyzer bug)',
        message: "'${w.qualifiedName}' ${w.message}",
      );
    }
    for (final problem in result.problems) {
      final file = _escapeProperty(
        _annotationFile(problem.filePath, pathPrefix),
      );
      final position = [
        if (problem.line case final line?) 'line=$line',
        if (problem.column case final column?) 'col=$column',
      ];
      final name = problem.name == null ? '' : "'${problem.name}': ";
      buffer.writeln(
        '::warning '
        '${['file=$file', ...position, 'title=Could not analyze'].join(',')}'
        '::${_escapeData('$name${problem.summary} Cause: ${problem.cause}')}',
      );
    }
    return buffer.toString();
  }

  static String _annotationFile(String filePath, String pathPrefix) =>
      pathPrefix == '.' || pathPrefix.isEmpty
      ? filePath
      : p.posix.normalize('$pathPrefix/$filePath');

  static void _writeAnnotation(
    StringBuffer buffer,
    UnusedDeclaration decl,
    String pathPrefix, {
    required String level,
    required String title,
    required String message,
  }) => _writeAnnotationRaw(
    buffer,
    _annotationFile(decl.filePath, pathPrefix),
    decl.line,
    decl.column,
    level: level,
    title: title,
    message: message,
  );

  static void _writeAnnotationRaw(
    StringBuffer buffer,
    String file,
    int line,
    int col, {
    required String level,
    required String title,
    required String message,
  }) {
    buffer.writeln(
      '::$level '
      'file=${_escapeProperty(file)},'
      'line=$line,'
      'col=$col,'
      'title=${_escapeProperty(title)}'
      '::${_escapeData(message)}',
    );
  }

  // Escaping per the workflow-command spec.
  static String _escapeData(String value) => value
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');

  static String _escapeProperty(String value) =>
      _escapeData(value).replaceAll(':', '%3A').replaceAll(',', '%2C');

  static String _summary(FinderResult result, Style style) {
    final count = result.unused.length;
    final fileCount = result.unused.map((d) => d.filePath).toSet().length;
    final seconds = (result.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    final headline = count == 0
        ? style.success('No unused declarations found')
        : style.attention(
            'Found ${plural(count, 'unused declaration')} in '
            '${plural(fileCount, 'file')}',
          );
    final scanned = style.note(
      '(scanned ${plural(result.filesScanned, 'file')}, '
      '${plural(result.declarationsChecked, 'declaration')}, ${seconds}s)',
    );
    final sections = [
      if (result.docOnly.isNotEmpty) '${result.docOnly.length} doc-only',
      if (result.recoveredReferences.isNotEmpty)
        style.caution('${result.recoveredReferences.length} recovered'),
      if (result.problems.isNotEmpty)
        style.caution('${result.problems.length} not analyzed'),
    ];
    return ['$headline $scanned', ...sections].join(style.note(' · '));
  }
}
