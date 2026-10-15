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

/// A declaration that had no reported references but was confirmed used by the
/// secondary definition check. Surfaced as a warning so the missed reference
/// can be looked into.
class RecoveredReference {
  const RecoveredReference({
    required this.name,
    required this.filePath,
    required this.line,
    required this.column,
    required this.usageFilePath,
    required this.usageLine,
    required this.usageColumn,
    this.container,
  });

  /// Simple (unqualified) name of the recovered declaration.
  final String name;

  /// Enclosing declaration name (e.g. the class for a method), if any.
  final String? container;

  /// Declaration location (root-relative `/`-path, one-based line/column).
  final String filePath;
  final int line;
  final int column;

  /// The confirmed usage location.
  final String usageFilePath;
  final int usageLine;
  final int usageColumn;

  /// Fully qualified display name, e.g. `MyClass.myMethod`.
  String get qualifiedName =>
      container?.let((container) => '$container.$name') ?? name;

  /// Channel-neutral explanation; callers prepend the name and declaration
  /// location as their output format needs.
  String get message =>
      'used at $usageFilePath:$usageLine:$usageColumn, but the Dart analyzer '
      'did not report this reference (find-references returned none); recovered '
      'via definition — likely a Dart SDK find-references bug';

  Map<String, Object?> toJson() => {
    'name': name,
    'qualifiedName': qualifiedName,
    'container': ?container,
    'file': filePath,
    'line': line,
    'column': column,
    'usageFile': usageFilePath,
    'usageLine': usageLine,
    'usageColumn': usageColumn,
    'message': message,
  };
}

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

/// A pair of range comments, such as `// coverage:ignore-start` and
/// `// coverage:ignore-end`, with nothing but whitespace and comments between
/// them: its file, relative to the root and with `/`, the opening comment's
/// one-based line, and the two markers.
typedef EmptyRange = ({String filePath, int line, String open, String close});

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
    this.recoveredReferences = const [],
    this.problems = const [],
    this.emptiedContainers = const [],
    this.emptyRanges = const [],
  });

  /// Declarations with zero references of any kind — the tool's actual
  /// "unused" verdict. Sorted by file then position. These, and only these,
  /// are eligible for `--remove`.
  final List<UnusedDeclaration> unused;

  /// Declarations with no *code* references, but at least one dartdoc
  /// `[Xxx]`-style comment link — informational, not a removal candidate.
  /// A link resolves to a real declaration, so the analysis server counts it
  /// as a reference; reporting these separately surfaces likely-dead code
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
  bool get hasFindings =>
      unused.isNotEmpty || emptyFiles.isNotEmpty || emptyRanges.isNotEmpty;

  /// Number of files scanned for declarations.
  final int filesScanned;

  /// Number of declarations whose references were checked.
  final int declarationsChecked;

  /// Wall-clock time the run took.
  final Duration elapsed;

  /// Declarations confirmed used by the secondary definition check despite
  /// having no reported references — surfaced as warnings, not findings.
  final List<RecoveredReference> recoveredReferences;

  /// What the run could not analyze. Affected code is kept, so a problem can
  /// hide a finding but never adds one.
  final List<AnalysisProblem> problems;

  /// The classes, mixins and extensions that `--remove` leaves with an empty
  /// body: each of their members is a removable finding, but other code still
  /// uses them. Sorted by file, then name.
  final List<EmptiedContainer> emptiedContainers;

  /// The empty ranges in the scanned files, sorted by file, then line. Those
  /// in [emptyFiles] and [emptyVariants] are left out.
  final List<EmptyRange> emptyRanges;
}
