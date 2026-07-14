/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

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

/// Configuration for a single run of the finder.
class FinderOptions {
  /// Creates options for analyzing the package rooted at [rootPath].
  const FinderOptions({
    required this.rootPath,
    this.includeGlobs = const [],
    this.excludeGlobs = const [],
    this.kinds = defaultKinds,
    this.includePublic = true,
    this.includeGenerated = false,
    this.additionalGeneratedSuffixes = const [],
    this.skipOverrides = true,
    this.skipOperators = true,
    this.concurrency = 16,
    this.dartExecutable,
    this.onProgress,
  }) : assert(concurrency > 0, 'concurrency must be positive');

  /// Absolute path to the package root to analyze.
  final String rootPath;

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

  /// Whether to scan generated files (`*.g.dart`, `*.freezed.dart`, …).
  final bool includeGenerated;

  /// Extra filename suffixes to treat as generated, in addition to the
  /// built-in set (`.g.dart`, `.freezed.dart`, …). Lets projects whose code
  /// generators emit a custom suffix (e.g. `.gc.dart`) exclude those files
  /// from the scan without also opting every generated file back in.
  ///
  /// Each entry is matched with a plain `endsWith` against the file's name, so
  /// values should include the leading dot and the `.dart` extension (e.g.
  /// `.gc.dart`). Ignored when [includeGenerated] is set (everything is
  /// scanned then).
  final List<String> additionalGeneratedSuffixes;

  /// Whether to skip declarations annotated with `@override` (they are usually
  /// reached polymorphically, which a plain reference search can miss).
  final bool skipOverrides;

  /// Whether to skip operator overloads (`operator +`, `operator ==`, …).
  /// The analysis server's reference search does not resolve infix operator
  /// syntax (`a + b`) back to the operator's declaration, so a used operator
  /// overload is reported as unused every time — on by default to avoid that
  /// false positive.
  final bool skipOperators;

  /// How many `textDocument/references` requests to keep in flight at once.
  /// Higher values keep the analysis server busier; there are diminishing
  /// returns past its internal parallelism.
  final int concurrency;

  /// Path to the `dart` executable used to launch the analysis server.
  /// Defaults to the SDK currently running this tool.
  final String? dartExecutable;

  /// Optional progress callback, invoked with a human-readable status line.
  final void Function(String message)? onProgress;

  /// The declaration kinds reported by default. Deliberately excludes
  /// [SymbolKind.typeParameter] (always "used" within its scope) and the
  /// primitive value kinds the server never emits for Dart declarations.
  ///
  /// Operator overloads are *not* a separate kind here: the analysis server
  /// reports them as plain [SymbolKind.method] declarations named `+`, `==`,
  /// etc. — see [skipOperators] for how they're excluded by default instead.
  static const defaultKinds = <SymbolKind>{
    .class$,
    .interface$,
    .enum$,
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
    this.container,
    this.isEnumValue = false,
  });

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

  /// The full source span of the declaration (including its body), used to
  /// locate it again for removal. Unlike [line]/[column] (the name's
  /// position), this covers the whole node.
  final DeclarationRange range;

  /// Whether this is an enum value (e.g. `south` in `enum Direction`).
  /// Removing one requires also tidying up a neighboring comma, unlike other
  /// declaration kinds.
  final bool isEnumValue;

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
}
