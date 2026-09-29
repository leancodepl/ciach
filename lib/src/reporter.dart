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
import 'package:ciach/src/style.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Renders a [FinderResult] for humans or machines.
abstract final class Reporter {
  /// A grouped, aligned, human-readable report.
  static String text(FinderResult result, {Style style = Style.plain}) {
    final buffer = StringBuffer();
    _writeGroup(buffer, result.unused, style);

    if (result.docOnly.isNotEmpty) {
      buffer.writeln(
        style.hint(
          'Referenced only from doc comments — not counted as unused, '
          'never removed:',
        ),
      );
      _writeGroup(buffer, result.docOnly, style);
    }

    buffer.write(_summary(result, style));
    return buffer.toString();
  }

  /// Writes one file-grouped, aligned block of [decls] to [buffer].
  static void _writeGroup(
    StringBuffer buffer,
    List<UnusedDeclaration> decls,
    Style style,
  ) {
    for (final MapEntry(key: file, value: fileDecls)
        in decls.groupListsBy((d) => d.filePath).entries) {
      buffer.writeln(style.bold(file));

      // Column widths for tidy alignment (each group is non-empty).
      final locWidth = fileDecls.map((d) => '${d.line}:${d.column}'.length).max;
      final kindWidth = fileDecls.map((d) => d.kind.label.length).max;

      for (final decl in fileDecls) {
        final loc = '${decl.line}:${decl.column}'.padRight(locWidth);
        final kind = decl.kind.label.padRight(kindWidth);
        final visibility = decl.isPrivate ? 'private' : 'public';
        final blocked = decl.removalBlocked
            ? '  ${style.yellow('(unsafe to auto-remove — remove manually)')}'
            : '';
        final hint = decl.hint != null
            ? '  ${style.hint('(${decl.hint})')}'
            : '';
        buffer.writeln(
          '  ${style.hint(loc)}  '
          '${style.cyan(kind)}  '
          '${decl.qualifiedName}  '
          '${style.hint('($visibility)')}'
          '$blocked$hint',
        );
      }
      buffer.writeln();
    }
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

  /// Recovery warnings for stderr (text format), one per line, or empty.
  static String warningsText(FinderResult result, {Style style = Style.plain}) {
    final buffer = StringBuffer();
    for (final w in result.recoveredReferences) {
      buffer.writeln(
        "${style.warning('warning:')} '${w.qualifiedName}' "
        "${style.hint('(${w.filePath}:${w.line}:${w.column})')} ${w.message}",
      );
    }
    return buffer.toString();
  }

  /// The run's [FinderResult.problems] for stderr (text format), grouped by
  /// what failed and why, or empty. [verbose] lists every location, with the
  /// analysis server's stack traces; otherwise each group shows the first
  /// [maxListed].
  static String problemsText(
    FinderResult result, {
    bool verbose = false,
    Style style = Style.plain,
    int maxListed = 10,
  }) {
    final buffer = StringBuffer();
    var hasDetail = false;
    for (final MapEntry(key: summary, value: ofSummary)
        in result.problems.groupListsBy((p) => p.summary).entries) {
      buffer.writeln('${style.warning('warning:')} $summary');
      for (final MapEntry(key: cause, value: problems)
          in ofSummary.groupListsBy((p) => p.cause).entries) {
        buffer.writeln('  ${style.bold('Cause:')} $cause');
        final listed = verbose ? problems : problems.take(maxListed);
        final width = listed.map((p) => p.location.length).max;
        for (final problem in listed) {
          final name = problem.name == null ? '' : '  ${problem.name}';
          buffer.writeln(
            '    ${style.hint(problem.location.padRight(width))}'
            '$name',
          );
        }
        if (problems.length > listed.length) {
          buffer.writeln(
            style.hint(
              '    … and ${problems.length - listed.length} more '
              '(--verbose lists them all)',
            ),
          );
        }
        final detail = problems.first.detail;
        hasDetail |= detail != null;
        if (verbose && detail != null) {
          buffer
            ..writeln('  The analysis server logged, for the first:')
            ..writeln(detail.split('\n').map((line) => '    $line').join('\n'));
        }
      }
    }
    if (hasDetail && !verbose) {
      buffer.writeln(
        style.hint(
          'The analysis server threw while answering, which is likely a Dart '
          'SDK bug; --verbose shows its stack trace.',
        ),
      );
    }
    return buffer.toString();
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
        message:
            "Unused ${decl.isPrivate ? 'private ' : ''}${decl.kind.label} "
            "'${decl.qualifiedName}'"
            "${decl.hint != null ? ' — ${decl.hint}' : ''}",
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
    final docOnlyCount = result.docOnly.length;
    final problemCount = result.problems.length;
    final scanned = style.hint(
      '(scanned ${result.filesScanned} files, '
      '${result.declarationsChecked} declarations, ${seconds}s).',
    );
    final headline = count == 0
        ? style.success('No unused declarations found')
        : style.bold(
            'Found $count unused declaration${count == 1 ? '' : 's'} '
            'in $fileCount file${fileCount == 1 ? '' : 's'}',
          );
    final docOnly = docOnlyCount == 0
        ? ''
        : ' $docOnlyCount more referenced only from doc comments.';
    final problems = problemCount == 0
        ? ''
        : ' ${style.yellow('$problemCount part${problemCount == 1 ? '' : 's'} of '
          'the analysis failed — see the warnings.')}';
    return '$headline $scanned$docOnly$problems';
  }
}
