/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

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
    this.exportedPackages = const [],
    this.includeGenerated = false,
    this.additionalGeneratedGlobs = const [],
    this.skipOverrides = true,
    this.skipOperators = true,
    this.unusedUnionMembers = false,
    this.reportToJson = false,
    this.transitive = true,
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

  /// Whether to report public declarations: those whose name doesn't start
  /// with `_`, other than an unnamed extension and its members. Private
  /// declarations are always reported when unused.
  final bool includePublic;

  /// Globs, relative to [rootPath], of the packages that packages outside the
  /// analysis import, so what they can import is not reported: libraries in
  /// `lib/` outside `lib/src/`, and what those export. Empty by default, which
  /// checks the API of every package.
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
  /// marked as blocked for removal (`UnusedDeclaration.removalBlocked`).
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
  /// `--remove` would delete, repeating until nothing new is found, and dead
  /// declarations that only reference each other, in a cycle. Each such
  /// finding names what it is only referenced from. Off, only what nothing
  /// references at all is reported; the rest shows up after a removal and
  /// another run.
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
  /// `extension type` shares it and is remapped to [SymbolKind.struct]. A
  /// type alias, function type aliases included, is [SymbolKind.object].
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
    .object,
  };
}
