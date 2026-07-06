/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// Finds declarations that are never referenced in a Dart/Flutter package by
/// driving the Dart analysis server over LSP.
///
/// The primary entry point is `UnusedDeclarationsFinder`: configure it with
/// `FinderOptions`, call `run()`, and inspect the `FinderResult`'s
/// `UnusedDeclaration`s.
///
/// ```dart
/// final result = await UnusedDeclarationsFinder(
///   FinderOptions(rootPath: 'path/to/package', includePublic: false),
/// ).run();
/// for (final decl in result.unused) {
///   print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
/// }
/// ```
library;

export 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

export 'src/finder.dart' show UnusedDeclarationsFinder;
export 'src/models.dart'
    show FinderOptions, FinderResult, SymbolKindLabel, UnusedDeclaration;
