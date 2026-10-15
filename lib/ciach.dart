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
/// The primary entry point is `Ciach`: configure it with
/// `FinderOptions`, call `run()`, and inspect the `FinderResult`'s
/// `UnusedDeclaration`s.
///
/// ```dart
/// final result = await Ciach(
///   FinderOptions(rootPath: 'path/to/package', includePublic: false),
/// ).run();
/// for (final decl in result.unused) {
///   print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
/// }
/// ```
library;

export 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

export 'src/conventions/entry_points.dart' show EntryPoint;
export 'src/finder.dart' show Ciach;
export 'src/lsp/dart_executable.dart'
    show DartSdkNotFoundException, findDartExecutable;
export 'src/lsp/exceptions.dart'
    show AnalysisServerExitedException, LspRequestException;
export 'src/model/finder_options.dart' show FinderOptions;
export 'src/model/finder_result.dart'
    show
        AnalysisProblem,
        EmptiedContainer,
        EmptyRange,
        FinderResult,
        RecoveredReference;
export 'src/model/removal_result.dart'
    show DeletedFile, LeftComment, RemovalResult;
export 'src/model/unused_declaration.dart'
    show
        CoupledRemoval,
        DeadReferrer,
        DeclarationRange,
        SymbolKindLabel,
        UnusedDeclaration;
export 'src/project_config/project_config.dart' show ProjectConfig;
export 'src/remove/remover.dart' show RemovalException, removeDeclarations;
export 'src/workspace/packages.dart' show UnresolvedPackagesException;
