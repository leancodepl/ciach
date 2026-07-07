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
import 'package:path/path.dart' as p;

/// Renders a [FinderResult] for humans or machines.
abstract final class Reporter {
  /// A grouped, aligned, human-readable report.
  static String text(FinderResult result, {bool useColor = false}) {
    final buffer = StringBuffer();
    final byFile = <String, List<UnusedDeclaration>>{};
    for (final decl in result.unused) {
      byFile.putIfAbsent(decl.filePath, () => []).add(decl);
    }

    for (final entry in byFile.entries) {
      buffer.writeln(_style(entry.key, _bold, useColor));

      // Column widths for tidy alignment.
      final locWidth = entry.value
          .map((d) => '${d.line}:${d.column}'.length)
          .fold(0, (a, b) => a > b ? a : b);
      final kindWidth = entry.value
          .map((d) => d.kind.label.length)
          .fold(0, (a, b) => a > b ? a : b);

      for (final decl in entry.value) {
        final loc = '${decl.line}:${decl.column}'.padRight(locWidth);
        final kind = decl.kind.label.padRight(kindWidth);
        final visibility = decl.isPrivate ? 'private' : 'public';
        buffer.writeln(
          '  ${_style(loc, _dim, useColor)}  '
          '${_style(kind, _cyan, useColor)}  '
          '${decl.qualifiedName}  '
          '${_style('($visibility)', _dim, useColor)}',
        );
      }
      buffer.writeln();
    }

    buffer.write(_summary(result));
    return buffer.toString();
  }

  /// A machine-readable JSON report.
  static String json(FinderResult result) {
    const encoder = JsonEncoder.withIndent('  ');
    return encoder.convert({
      'summary': {
        'filesScanned': result.filesScanned,
        'declarationsChecked': result.declarationsChecked,
        'unusedCount': result.unused.length,
        'elapsedMs': result.elapsed.inMilliseconds,
      },
      'unused': [for (final decl in result.unused) decl.toJson()],
    });
  }

  /// [GitHub Actions workflow commands][] — one `::warning` annotation per
  /// finding, so unused declarations surface inline on the PR diff and Checks
  /// tab.
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
      final file = pathPrefix == '.' || pathPrefix.isEmpty
          ? decl.filePath
          : p.posix.normalize('$pathPrefix/${decl.filePath}');
      final visibility = decl.isPrivate ? 'private ' : '';
      final message =
          "Unused $visibility${decl.kind.label} '${decl.qualifiedName}'";
      buffer.writeln(
        '::warning '
        'file=${_escapeProperty(file)},'
        'line=${decl.line},'
        'col=${decl.column},'
        'title=Unused declaration'
        '::${_escapeData(message)}',
      );
    }
    return buffer.toString();
  }

  // Escaping per the workflow-command spec.
  static String _escapeData(String value) => value
      .replaceAll('%', '%25')
      .replaceAll('\r', '%0D')
      .replaceAll('\n', '%0A');

  static String _escapeProperty(String value) =>
      _escapeData(value).replaceAll(':', '%3A').replaceAll(',', '%2C');

  static String _summary(FinderResult result) {
    final count = result.unused.length;
    final fileCount = result.unused.map((d) => d.filePath).toSet().length;
    final seconds = (result.elapsed.inMilliseconds / 1000).toStringAsFixed(1);
    if (count == 0) {
      return 'No unused declarations found '
          '(scanned ${result.filesScanned} files, '
          '${result.declarationsChecked} declarations, ${seconds}s).';
    }
    return 'Found $count unused declaration${count == 1 ? '' : 's'} '
        'in $fileCount file${fileCount == 1 ? '' : 's'} '
        '(scanned ${result.filesScanned} files, '
        '${result.declarationsChecked} declarations, ${seconds}s).';
  }

  // Minimal ANSI styling helpers.
  static const _bold = '1';
  static const _dim = '2';
  static const _cyan = '36';

  static String _style(String text, String code, bool useColor) =>
      useColor ? '\x1b[${code}m$text\x1b[0m' : text;
}
