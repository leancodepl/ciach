/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/model/removal_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/report/annotations.dart';
import 'package:ciach/src/report/style.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';

/// The human-readable report: findings, extra sections, summary. Unless
/// [verbose], each problem cause lists at most [maxListed] locations.
String textReport(
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
      emptyFileContents,
      style,
    );
    final variants = result.emptyVariants.toSet();
    for (final file in empty) {
      buffer.writeln(
        [
          style.path(file),
          if (variants.contains(file)) style.caution('($emptyVariantNote)'),
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
String removalReport(
  RemovalResult? removal, {
  int removed = 0,
  int blocked = 0,
  List<EmptiedContainer> emptied = const [],
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
    if (deleted.isNotEmpty)
      'Deleted ${plural(deleted.length, 'empty file', 'empty files')}: ${deleted.map((d) => d.filePath).join(', ')}.',
    if (emptied.isNotEmpty)
      style.caution(
        'Left ${plural(emptied.length, 'declaration', 'declarations')} empty because other code still uses them: ${emptied.map((e) => '${e.name} (${e.filePath})').join(', ')}.',
      ),
    style.note("Run 'dart format' to tidy up spacing."),
  ];
  final buffer = StringBuffer(sentences.join(' '));
  if (removal.leftComments case final comments when comments.isNotEmpty) {
    buffer.write(
      '\n${style.caution('Kept ${plural(comments.length, 'comment', 'comments')} that sat right above removed code. Check whether ${comments.length == 1 ? 'it' : 'each'} still belongs:')}',
    );
    for (final (:filePath, :line) in comments) {
      buffer.write('\n  $filePath:$line');
    }
  }
  for (final note in notes) {
    buffer.write('\n${style.heading('Note:')} $note');
  }
  return buffer.toString();
}

/// A section heading.
void _writeHeading(
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
void _writeDeclarations(
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

void _writeRecovered(
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
void _writeProblems(
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

void _writeCause(
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
        style.note(detail.split('\n').map((line) => '      $line').join('\n')),
      );
  }
}

void _writeProblemRows(
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
List<String> _notes(UnusedDeclaration decl, Style style) => [
  if (decl.removalBlocked)
    style.caution('(unsafe to auto-remove — remove manually)'),
  if (decl.hint case final hint?) style.note('($hint)'),
  if (onlyReferencedFromNote(decl) case final referrers?)
    style.note('($referrers)'),
];

String _summary(FinderResult result, Style style) {
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
