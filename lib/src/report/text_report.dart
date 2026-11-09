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
  final empty = result.allEmptyFiles;
  final variants = result.emptyVariants.toSet();
  return [
    ..._declarationLines(result.unused, style),
    if (empty.isNotEmpty) ...[
      _heading('Empty files', empty.length, emptyFileContents, style),
      for (final file in empty)
        [
          style.path(file),
          if (variants.contains(file)) style.caution('($emptyVariantNote)'),
        ].join('  '),
      '',
    ],
    if (result.docOnly.isNotEmpty) ...[
      _heading(
        'Referenced only from doc comments',
        result.docOnly.length,
        'not counted, never removed',
        style,
      ),
      ..._declarationLines(result.docOnly, style),
    ],
    if (result.problems.isNotEmpty) ...[
      _heading(
        'Not analyzed',
        result.problems.length,
        'the analysis failed here',
        style,
        caution: true,
      ),
      ..._problemLines(result.problems, style, verbose, maxListed),
    ],
    _summary(result, style),
  ].join('\n');
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
    style.note('Run `dart format` to tidy up spacing.'),
  ];
  return [
    sentences.join(' '),
    if (deleted.isNotEmpty) ...[
      'Deleted ${plural(deleted.length, 'empty file', 'empty files')}:',
      for (final file in deleted) '  ${file.filePath}',
    ],
    if (emptied.isNotEmpty) ...[
      style.caution(
        'Left ${plural(emptied.length, 'declaration', 'declarations')} empty because other code still uses them:',
      ),
      for (final (:filePath, :name) in emptied) '  $name ($filePath)',
    ],
    if (removal.leftComments case final comments when comments.isNotEmpty) ...[
      style.caution(
        'Kept ${plural(comments.length, 'comment', 'comments')} that sat right above removed code. Check whether ${comments.length == 1 ? 'it' : 'each'} still belongs:',
      ),
      for (final (:filePath, :line) in comments) '  $filePath:$line',
    ],
    for (final note in notes) '${style.heading('Note:')} $note',
  ].join('\n');
}

/// A section heading.
String _heading(
  String title,
  int count,
  String meaning,
  Style style, {
  bool caution = false,
}) {
  final heading = style.heading('$title ($count)');
  return '${caution ? style.caution(heading) : heading} ${style.note('· $meaning')}';
}

/// The lines of one file-grouped, aligned block of [decls].
Iterable<String> _declarationLines(
  List<UnusedDeclaration> decls,
  Style style,
) sync* {
  for (final MapEntry(key: file, value: fileDecls)
      in decls.groupListsBy((d) => d.filePath).entries) {
    yield style.path(file);

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
      yield '  ${columns.join('  ')}';
    }
    yield '';
  }
}

/// The lines of [problems], grouped by summary, cause, then file.
Iterable<String> _problemLines(
  List<AnalysisProblem> problems,
  Style style,
  bool verbose,
  int maxListed,
) sync* {
  for (final MapEntry(key: summary, value: ofSummary)
      in problems.groupListsBy((p) => p.summary).entries) {
    yield '  $summary';
    for (final MapEntry(key: cause, value: ofCause)
        in ofSummary.groupListsBy((p) => p.cause).entries) {
      yield* _causeLines(cause, ofCause, style, verbose, maxListed);
    }
  }
  yield '';
}

Iterable<String> _causeLines(
  String cause,
  List<AnalysisProblem> ofCause,
  Style style,
  bool verbose,
  int maxListed,
) sync* {
  yield '    ${style.failure(cause)}';
  final listed = verbose ? ofCause : ofCause.take(maxListed).toList();
  for (final MapEntry(key: file, value: inFile)
      in listed.groupListsBy((p) => p.filePath).entries) {
    yield '    ${style.path(file)}';
    yield* _problemRows(inFile, style);
  }
  if (ofCause.length > listed.length) {
    yield style.note(
      '    … and ${ofCause.length - listed.length} more (-v lists them all)',
    );
  }
}

Iterable<String> _problemRows(List<AnalysisProblem> inFile, Style style) sync* {
  final rows = inFile.where((p) => p.line != null).toList();
  if (rows.isEmpty) {
    return;
  }
  final locWidth = rows.map((p) => '${p.line}:${p.column ?? 1}'.length).max;
  for (final p in rows) {
    final loc = '${p.line}:${p.column ?? 1}'.padRight(locWidth);
    yield '      ${[style.position(loc), ?p.name].join('  ')}';
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
    if (result.problems.isNotEmpty)
      style.caution('${result.problems.length} not analyzed'),
  ];
  return ['$headline $scanned', ...sections].join(style.note(' · '));
}
