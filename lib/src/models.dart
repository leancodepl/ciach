/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/paths.dart';
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

/// The kinds of declaration that can share a statement with others, like `a`
/// and `b` in `int a = 1, b = 2;`. The `range` of one covers only `a = 1`, so
/// `--remove` deletes its [UnusedDeclaration.cut] instead.
const declaratorKinds = <SymbolKind>{.field, .variable, .constant};

/// A declaration to remove together with a reported one. It names its own
/// `filePath` (relative to the analyzed root, `/`-separated), so it can live in
/// another file, like a dead `StatefulWidget`'s `State` subclass.
///
/// `range`, `fullRange`, `kind` and `cut` mean what they do on
/// [UnusedDeclaration].
typedef CoupledRemoval = ({
  String filePath,
  SymbolKind kind,
  DeclarationRange range,
  DeclarationRange fullRange,
  DeclarationRange? cut,
});

/// Configuration for a single run of the finder.
class FinderOptions {
  /// Creates options for analyzing the package rooted at [rootPath].
  ///
  /// [rootPath] and [analysisRootPath] may be relative; both are stored
  /// absolute and normalized.
  FinderOptions({
    required String rootPath,
    String? analysisRootPath,
    this.includeGlobs = const [],
    this.excludeGlobs = const [],
    this.kinds = defaultKinds,
    this.includePublic = true,
    this.exportedPackages = const ['**'],
    this.includeGenerated = false,
    this.additionalGeneratedGlobs = const [],
    this.skipOverrides = true,
    this.skipOperators = true,
    this.unusedUnionMembers = false,
    this.reportToJson = false,
    this.transitive = false,
    this.entryPoints = const [],
    this.translations = const [],
    this.concurrency = 16,
    this.dartExecutable,
  }) : rootPath = rootPath.absoluteNormalized,
       analysisRootPath = analysisRootPath?.absoluteNormalized,
       assert(concurrency > 0, 'concurrency must be positive');

  /// The package root to analyze, absolute and normalized.
  final String rootPath;

  /// The directory the analysis server is pointed at, absolute and normalized,
  /// for references outside [rootPath] — a sibling package depending on it by
  /// `path:`. Must contain [rootPath]; `null` (the default) means [rootPath].
  ///
  /// Only reference counting widens: candidates, reported paths and the
  /// include/exclude globs stay on [rootPath]. A pub workspace needs no
  /// setting.
  final String? analysisRootPath;

  /// If non-empty, only files matching one of these globs (relative to
  /// [rootPath]) are scanned for declarations.
  final List<String> includeGlobs;

  /// Files matching any of these globs (relative to [rootPath]) are skipped.
  final List<String> excludeGlobs;

  /// Which symbol kinds are considered declarations worth reporting.
  final Set<SymbolKind> kinds;

  /// Whether to report public declarations (those not starting with `_`).
  /// Private declarations are always reported when unused.
  final bool includePublic;

  /// Globs, relative to [rootPath], of the packages that packages outside the
  /// analysis import, so what they can import is not reported: libraries in
  /// `lib/` outside `lib/src/`, and what those export. By default every
  /// package; an empty list checks the API of every package.
  final List<String> exportedPackages;

  /// Whether to scan generated files (`*.g.dart`, `*.freezed.dart`, …).
  final bool includeGenerated;

  /// Globs, relative to [rootPath], of more files to treat as generated: read
  /// for references, never reported or edited. For output a suffix can't pick
  /// out, like `flutter gen-l10n`'s `lib/l10n/**`, or code that isn't generated
  /// but is kept as is, like a vendored copy. Ignored when [includeGenerated]
  /// is set.
  final List<String> additionalGeneratedGlobs;

  /// Whether to skip declarations annotated with `@override` (they are usually
  /// reached polymorphically, which a plain reference search can miss).
  final bool skipOverrides;

  /// Whether to skip operator overloads (`operator +`, `operator ==`, …).
  /// The analysis server's reference search does not resolve infix operator
  /// syntax (`a + b`) back to the operator's declaration, so a used operator
  /// overload is reported as unused every time — on by default to avoid that
  /// false positive.
  final bool skipOperators;

  /// Whether to also flag a class as dead when its only non-self references
  /// are *type patterns* over its (sealed) supertype — `case` patterns in
  /// `switch` statements / `if`-`case` / `while`-`case` headers, or
  /// switch-*expression* arms — i.e. the type is *matched* but never
  /// *constructed* anywhere.
  ///
  /// Off by default, and deliberately so: a `case Foo():` arm normally counts
  /// as a real use of `Foo`, keeping it alive. When enabled, such a member is
  /// **reported** as an unused `class` so a human can see it is never
  /// constructed — but this is *report-only*: `--remove` deliberately leaves it
  /// (and its pattern arms) in place, because removing a member of a sealed
  /// union and rewriting the now-non-exhaustive `switch`es over it is a source
  /// rewrite this tool won't attempt. Every finding surfaced by this flag is
  /// marked [UnusedDeclaration.removalBlocked].
  ///
  /// Detection is conservative: only a reference that is confidently a type
  /// pattern is discounted; anything else (construction, type annotations,
  /// nested sub-patterns, pattern-variable declarations) keeps the class alive.
  final bool unusedUnionMembers;

  /// Whether to report a `toJson()` serialization hook as unused. Off by
  /// default: `jsonEncode(obj)` calls `obj.toJson()` by dynamic dispatch with no
  /// source-level `.toJson()` token, so the reference search can't see that use
  /// and would flag a live serializer. Enable to audit genuinely-dead `toJson`s.
  final bool reportToJson;

  /// Whether to also report declarations referenced only from findings
  /// `--remove` would delete, repeating until nothing new is found. Off by
  /// default, because one false positive also flags everything only it
  /// referenced. Dead declarations that only reference each other, in a
  /// cycle, are reported too.
  final bool transitive;

  /// The project's own entry points, on top of [EntryPoint.builtIn]. A match
  /// is never a candidate, so it is neither reported nor removed.
  final List<EntryPoint> entryPoints;

  /// The `gen-l10n` template files that are scanned for unused messages. The
  /// findings in these files are report-only.
  final List<Translations> translations;

  /// How many `textDocument/references` requests to keep in flight at once.
  /// Higher values keep the analysis server busier; there are diminishing
  /// returns past its internal parallelism.
  final int concurrency;

  /// Path to the `dart` executable used to launch the analysis server.
  /// Defaults to the SDK running this tool, or to `dart` from `PATH` when this
  /// is a compiled binary; see `findDartExecutable`.
  final String? dartExecutable;

  /// The declaration kinds reported by default. Deliberately excludes
  /// [SymbolKind.typeParameter] (always "used" within its scope) and the
  /// primitive value kinds the server never emits for Dart declarations.
  ///
  /// The server reports an `extension` as [SymbolKind.namespace]; an
  /// `extension type` shares it and is remapped to [SymbolKind.struct].
  ///
  /// Operator overloads are *not* a separate kind here: the analysis server
  /// reports them as plain [SymbolKind.method] declarations named `+`, `==`,
  /// etc. — see [skipOperators] for how they're excluded by default instead.
  static const defaultKinds = <SymbolKind>{
    .class$,
    .interface$,
    .enum$,
    .namespace,
    .struct,
    .function,
    .method,
    .constructor,
    .field,
    .property,
    .variable,
    .constant,
    .enumMember,
  };
}

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
    this.cut,
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

  /// For a `field`, `variable` or `constant`, the text `--remove` deletes: the
  /// whole statement when all its variables go, or this variable and one
  /// adjacent comma when others stay. `null` when the finder couldn't work it
  /// out; `--remove` then leaves the variable in place.
  final DeclarationRange? cut;

  /// Whether this is an enum value (e.g. `south` in `enum Direction`).
  /// Removing one requires also tidying up a neighboring comma, unlike other
  /// declaration kinds.
  final bool isEnumValue;

  /// Extra spans — each in a named file — that must be removed together with
  /// this declaration to keep the source compiling, but that are not
  /// themselves reported as findings.
  ///
  /// For example:
  ///
  /// - a dead `StatefulWidget`'s paired private `State<Widget>` subclass, which
  ///   is not independently "unused" (the widget's own `createState` references
  ///   it) yet becomes uncompilable the moment the widget is deleted
  ///   (`State<DeletedWidget>` no longer resolves).
  /// - every override of a dead member, which `skipOverrides` keeps out of the
  ///   findings and which would be left overriding nothing.
  /// - each `with` or `implements` clause entry that names a removed class or
  ///   mixin.
  ///
  /// Coupling a removal keeps `--remove` from breaking the build without
  /// surfacing the coupled span as a separate report entry.
  final List<CoupledRemoval> coupledRemovals;

  /// Whether this finding is real (the declaration is dead) but `--remove`
  /// must *not* delete it automatically, because doing so safely would require
  /// a source rewrite this tool won't attempt.
  ///
  /// Set for every dead sealed member surfaced by `--also union-members` (a
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

  /// This declaration with the given fields replaced.
  UnusedDeclaration copyWith({
    DeclarationRange? cut,
    List<CoupledRemoval>? coupledRemovals,
    bool? removalBlocked,
    String? hint,
  }) => .new(
    name: name,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    isPrivate: isPrivate,
    range: range,
    fullRange: fullRange,
    container: container,
    isEnumValue: isEnumValue,
    coupledRemovals: coupledRemovals ?? this.coupledRemovals,
    removalBlocked: removalBlocked ?? this.removalBlocked,
    hint: hint ?? this.hint,
    onlyReferencedFrom: onlyReferencedFrom,
    cut: cut ?? this.cut,
  );

  /// Fully qualified display name, e.g. `MyClass.myMethod`.
  String get qualifiedName =>
      container?.let((container) => '$container.$name') ?? name;

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

/// A class, mixin or extension that `--remove` leaves with an empty body.
/// `filePath` is relative to the root and uses `/`.
typedef EmptiedContainer = ({String filePath, String name});

/// A pair of range comments, such as `// coverage:ignore-start` and
/// `// coverage:ignore-end`, with nothing but whitespace and comments between
/// them: its file, relative to the root and with `/`, the opening comment's
/// one-based line, and the two markers.
typedef EmptyRange = ({String filePath, int line, String open, String close});

/// A `//` comment that `--remove` kept although it sat directly above removed
/// code: its file, relative to the root and with `/`, and its one-based line
/// in the rewritten file.
typedef LeftComment = ({String filePath, int line});

/// What `removeDeclarations` did.
class RemovalResult {
  const RemovalResult({
    required this.filesChanged,
    required this.deletedFiles,
    this.leftComments = const [],
    this.removedRanges = 0,
  });

  /// Files declarations were removed from, deleted ones included.
  final int filesChanged;

  final List<DeletedFile> deletedFiles;

  /// The `//` comments kept directly above removed code, which may have been
  /// about it. Sorted by file, then line.
  final List<LeftComment> leftComments;

  /// How many empty ranges were removed, with both their comments.
  final int removedRanges;
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
