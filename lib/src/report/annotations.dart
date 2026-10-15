/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// What every machine-readable report is built from: each finding of a run as
/// an annotation with a check, a location and a message.
library;

import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:path/path.dart' as p;

/// What an empty file holds.
const emptyFileContents =
    'nothing but comments and library, import or part-of directives';

/// What an empty range holds.
const emptyRangeContents = 'range comments with nothing between them';

/// Why `--remove` leaves an empty conditional-import variant.
const emptyVariantNote =
    'a conditional-import variant: remove its `if` clause and the file by hand';

/// What kind of finding an annotation is: its id and title, as the CI
/// services group and label it, and whether it is below a warning.
enum Check {
  unused('unused-declaration', 'Unused declaration'),
  emptyFile('empty-file', 'Empty file'),
  docOnly('doc-only', 'Referenced only from a doc comment', notice: true),
  recovered(
    'recovered-reference',
    'Recovered reference (possible analyzer bug)',
  ),
  notAnalyzed('not-analyzed', 'Could not analyze'),
  emptyRange('empty-range', 'Empty range');

  const Check(this.id, this.title, {this.notice = false});

  final String id;
  final String title;
  final bool notice;
}

/// One finding, where it is, and what to say about it.
typedef Annotation = ({
  Check check,
  String file,
  int? line,
  int? column,
  String message,
});

/// Every finding of [result] as an annotation, its path prefixed with
/// [pathPrefix]: unused declarations, empty files, empty ranges, doc-only
/// findings, recovered references and problems, in that order.
Iterable<Annotation> annotationsOf(
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
        ?onlyReferencedFromNote(decl),
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
        'Has $emptyFileContents',
        if (variants.contains(emptyFile)) emptyVariantNote,
      ].join(' — '),
    );
  }
  for (final (:filePath, :line, :open, :close) in result.emptyRanges) {
    yield (
      check: .emptyRange,
      file: file(filePath),
      line: line,
      column: null,
      message: 'Has $emptyRangeContents: // $open … // $close',
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

String _annotationFile(String filePath, String pathPrefix) =>
    pathPrefix == '.' || pathPrefix.isEmpty
    ? filePath
    : p.posix.normalize('$pathPrefix/$filePath');

/// The first finding [decl] is only referenced from, and how many others
/// there are; the JSON report lists them all.
String? onlyReferencedFromNote(UnusedDeclaration decl) {
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
