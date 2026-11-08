/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/util/extensions.dart';

/// A declaration or file whose analysis failed; the run went on without it.
class AnalysisProblem {
  const AnalysisProblem({
    required this.summary,
    required this.cause,
    required this.filePath,
    this.line,
    this.column,
    this.name,
    this.detail,
  });

  /// What failed and the fallback, e.g. "Could not find references; kept."
  /// Shared by problems of one kind.
  final String summary;

  /// The error, on one line.
  final String cause;

  /// Root-relative `/`-path; one-based line and column, when known.
  final String filePath;
  final int? line;
  final int? column;

  /// The declaration, e.g. `MyClass.myMethod`.
  final String? name;

  /// The server's stack trace, if any.
  final String? detail;

  /// `path:line:column`, as far as known.
  String get location => [filePath, ?line, ?column].join(':');

  @override
  String toString() =>
      '$location${name?.let((name) => ' ($name)') ?? ''}: $summary Cause: $cause';

  Map<String, Object?> toJson() => {
    'summary': summary,
    'cause': cause,
    'file': filePath,
    'line': ?line,
    'column': ?column,
    'name': ?name,
    'detail': ?detail,
  };
}

/// A class, mixin or extension that `--remove` leaves with an empty body.
/// `filePath` is relative to the root and uses `/`.
typedef EmptiedContainer = ({String filePath, String name});

/// The outcome of a finder run.
class FinderResult {
  /// Creates a result describing a completed finder run.
  const FinderResult({
    required this.unused,
    required this.docOnly,
    required this.filesScanned,
    required this.declarationsChecked,
    required this.elapsed,
    this.emptyFiles = const [],
    this.emptyVariants = const [],
    this.problems = const [],
    this.emptiedContainers = const [],
  });

  /// Declarations with zero references of any kind — the tool's actual
  /// "unused" verdict. Sorted by file then position. These, and only these,
  /// are eligible for `--remove`.
  final List<UnusedDeclaration> unused;

  /// Declarations with no *code* references, but at least one dartdoc
  /// `[Xxx]`-style comment link — informational, not a removal candidate.
  /// A link resolves to a real declaration, so it counts as a reference;
  /// reporting these separately surfaces likely-dead code
  /// without risking deletion of something that really is pointed to, just
  /// only from documentation. Sorted by file then position.
  final List<UnusedDeclaration> docOnly;

  /// Scanned files with nothing but comments and `library`, `import` or
  /// `part of` directives, as sorted root-relative `/`-paths. One that
  /// packages outside the analysis can import, by
  /// [FinderOptions.exportedPackages], is left out.
  final List<String> emptyFiles;

  /// Empty files a conditional import or export chooses between. Report-only:
  /// deleting one means rewriting that directive.
  final List<String> emptyVariants;

  /// [emptyFiles] and [emptyVariants] together, sorted.
  List<String> get allEmptyFiles => [...emptyFiles, ...emptyVariants]..sort();

  /// Whether there is anything `--remove` would act on.
  bool get hasFindings => unused.isNotEmpty || emptyFiles.isNotEmpty;

  /// Number of files scanned for declarations.
  final int filesScanned;

  /// Number of declarations whose references were checked.
  final int declarationsChecked;

  /// Wall-clock time the run took.
  final Duration elapsed;

  /// What the run could not analyze. Affected code is kept, so a problem can
  /// hide a finding but never adds one.
  final List<AnalysisProblem> problems;

  /// The classes, mixins and extensions that `--remove` leaves with an empty
  /// body: each of their members is a removable finding, but other code still
  /// uses them. Sorted by file, then name.
  final List<EmptiedContainer> emptiedContainers;
}
