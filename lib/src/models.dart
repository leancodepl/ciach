/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/finder_options.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

/// A `[start, end)` span within a file, using 0-based line/column positions
/// (columns are UTF-16 code units), matching the Language Server Protocol.
///
/// Identifies the full extent of a declaration — including its body — so it
/// can be located again for removal.
typedef DeclarationRange = ({
  int startLine,
  int startColumn,
  int endLine,
  int endColumn,
});

/// A declaration to remove together with a reported one. It names its own
/// `filePath` (relative to the analyzed root, `/`-separated), so it can live in
/// another file, like a dead `StatefulWidget`'s `State` subclass.
///
/// `range`, `fullRange` and `kind` mean what they do on [UnusedDeclaration];
/// the remover reads `kind` to tell a declarator from a whole node.
typedef CoupledRemoval = ({
  String filePath,
  SymbolKind kind,
  DeclarationRange range,
  DeclarationRange fullRange,
});

/// Human-friendly labels for [SymbolKind], used in reports.
extension SymbolKindLabel on SymbolKind {
  /// A short, lower-case label (e.g. `class`, `enum value`).
  String get label => switch (this) {
    .class$ => 'class',
    .enum$ => 'enum',
    .interface$ => 'interface',
    .namespace => 'extension',
    .struct => 'extension type',
    .operator$ => 'operator',
    .null$ => 'null',
    .enumMember => 'enum value',
    .typeParameter => 'type parameter',
    _ => name,
  };
}

/// A single declaration that the finder decided to report as unused.
class UnusedDeclaration {
  /// Creates a report entry for an unused declaration.
  const UnusedDeclaration({
    required this.name,
    required this.kind,
    required this.filePath,
    required this.line,
    required this.column,
    required this.isPrivate,
    required this.range,
    DeclarationRange? fullRange,
    this.container,
    this.isEnumValue = false,
    this.coupledRemovals = const [],
    this.removalBlocked = false,
    this.hint,
    this.onlyReferencedFrom = const [],
  }) : fullRange = fullRange ?? range;

  /// Simple (unqualified) name of the declaration.
  final String name;

  /// The kind of declaration (class, method, constructor, …).
  final SymbolKind kind;

  /// Path to the file, relative to the analyzed root, using `/` separators.
  final String filePath;

  /// One-based line of the declaration's name.
  final int line;

  /// One-based column of the declaration's name.
  final int column;

  /// Whether the declaration is library-private (name starts with `_`).
  final bool isPrivate;

  /// Enclosing declaration name (e.g. the class for a method), if any.
  final String? container;

  /// The declaration's code, body included. For a `field`, `variable` or
  /// `constant` it covers only that declarator.
  final DeclarationRange range;

  /// [range] extended to include the doc comment and annotations.
  final DeclarationRange fullRange;

  /// Whether this is an enum value (e.g. `south` in `enum Direction`).
  /// Removing one requires also tidying up a neighboring comma, unlike other
  /// declaration kinds.
  final bool isEnumValue;

  /// Extra whole-node spans — each in a named file — that must be removed
  /// together with this declaration to keep the source compiling, but that are
  /// not themselves reported as findings.
  ///
  /// Two uses today:
  ///
  /// - a dead `StatefulWidget`'s paired private `State<Widget>` subclass, which
  ///   is not independently "unused" (the widget's own `createState` references
  ///   it) yet becomes uncompilable the moment the widget is deleted
  ///   (`State<DeletedWidget>` no longer resolves).
  /// - every override of a dead member, which `skipOverrides` keeps out of the
  ///   findings and which would be left overriding nothing.
  ///
  /// Coupling a removal keeps `--remove` from breaking the build without
  /// surfacing the coupled span as a separate report entry.
  final List<CoupledRemoval> coupledRemovals;

  /// Whether this finding is real (the declaration is dead) but `--remove`
  /// must *not* delete it automatically, because doing so safely would require
  /// a source rewrite this tool won't attempt.
  ///
  /// Set for every dead sealed member surfaced by `--unused-union-members` (a
  /// class that is only ever *matched* by a type pattern, never constructed):
  /// deleting it would mean removing the member and rewriting every now-non-
  /// exhaustive `switch`/`if`-`case` over its supertype. Also set for a member
  /// whose override this tool won't delete — one in an unscanned file, or a
  /// declaring parameter — which would be left overriding nothing. The declaration is still
  /// reported so a human can act on it; it — and anything coupled to it — is
  /// simply skipped by the remover.
  final bool removalBlocked;

  /// An optional advisory note shown alongside the finding — extra context that
  /// doesn't change whether or how it is removed. Set for a sole, zero-parameter
  /// private constructor (`Foo._();`): it is reported and removable like any
  /// other dead code, but the note nudges toward `abstract final class` as the
  /// idiomatic way to make a static-only class non-instantiable.
  final String? hint;

  /// With [FinderOptions.transitive], the findings that held this
  /// declaration's only references, in source order. Empty when nothing
  /// referenced it at all.
  final List<DeadReferrer> onlyReferencedFrom;

  /// Fully qualified display name, e.g. `MyClass.myMethod`.
  String get qualifiedName => container == null ? name : '$container.$name';

  /// A JSON-encodable representation of this declaration.
  Map<String, Object?> toJson() => {
    'name': name,
    'qualifiedName': qualifiedName,
    'kind': kind.label,
    'file': filePath,
    'line': line,
    'column': column,
    'isPrivate': isPrivate,
    'container': ?container,
    'hint': ?hint,
    if (onlyReferencedFrom.isNotEmpty)
      'onlyReferencedFrom': [
        for (final referrer in onlyReferencedFrom)
          {
            'qualifiedName': referrer.qualifiedName,
            'file': referrer.filePath,
            'line': referrer.line,
          },
      ],
  };
}

/// A finding that references another one: its qualified name, its file
/// (root-relative, `/`-separated) and its one-based line.
typedef DeadReferrer = ({String qualifiedName, String filePath, int line});

/// A file `--remove` deleted, and the files unlinked from it. Root-relative
/// `/`-paths.
typedef DeletedFile = ({String filePath, List<String> unlinkedFrom});

/// What `removeDeclarations` did.
class RemovalResult {
  const RemovalResult({required this.filesChanged, required this.deletedFiles});

  /// Files declarations were removed from, deleted ones included.
  final int filesChanged;

  final List<DeletedFile> deletedFiles;
}

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
  String get qualifiedName => container == null ? name : '$container.$name';

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
      '$location${name == null ? '' : ' ($name)'}: $summary Cause: $cause';

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

/// The outcome of a finder run.
class FinderResult {
  /// Creates a result describing a completed finder run.
  const FinderResult({
    required this.unused,
    required this.docOnly,
    required this.filesScanned,
    required this.declarationsChecked,
    required this.elapsed,
    this.recoveredReferences = const [],
    this.problems = const [],
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
}
