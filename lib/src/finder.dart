/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'dart:async';
import 'dart:io';

import 'package:ciach/src/candidate_collector.dart';
import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/settler.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/verdict.dart';

/// Finds declarations that are never referenced by driving the Dart analysis
/// server over LSP.
///
/// For every declaration reported by `textDocument/documentSymbol`, a
/// `textDocument/references` query is issued at the declaration's name, with
/// `includeDeclaration: false`. An empty result means the declaration is unused.
///
/// `Ciach` owns the server session and the pipeline (discover → collect →
/// fetch → settle); each stage is a collaborator: [CandidateCollector] decides
/// what to check, [ReferenceFetch] asks the server, [Settler] turns the answers
/// into findings with [ReferenceClassifier] deciding used/unused, [Verdict]
/// deciding how a dead candidate is reported, and the `conventions/` rules
/// keeping framework-driven declarations alive.
class Ciach {
  /// Creates a finder that runs with the given [options].
  Ciach(this.options);

  /// The configuration for this run.
  final FinderOptions options;

  /// Lazily-cached source text and tokens for every file touched this run,
  /// shared by the classification and the structural detectors.
  final _sources = SourceIndex();

  /// Freezed-union tracking, fed as candidates are collected.
  final _freezed = FreezedUnions();

  late final _classifier = ReferenceClassifier(
    _sources,
    unusedUnionMembers: options.unusedUnionMembers,
  );

  late final _collector = CandidateCollector(
    options: options,
    sources: _sources,
    freezed: _freezed,
  );

  late final _fetch = ReferenceFetch(options: options, sources: _sources);

  late final _settler = Settler(
    options: options,
    sources: _sources,
    freezed: _freezed,
    classifier: _classifier,
    verdict: Verdict(
      options: options,
      sources: _sources,
      classifier: _classifier,
    ),
  );

  void _report(String message) => options.onProgress?.call(message);

  /// Runs the analysis and returns the declarations that are never referenced.
  ///
  /// Throws an [ArgumentError] if [FinderOptions.analysisRootPath] does not
  /// contain [FinderOptions.rootPath]; widening to a directory beside the
  /// scanned one would drop references rather than add them.
  Future<FinderResult> run() async {
    final stopwatch = Stopwatch()..start();
    final rootPath = options.rootPath;
    final analysisRoot = options.analysisRootPath ?? rootPath;
    if (!analysisRootContains(analysisRoot, rootPath)) {
      throw ArgumentError.value(
        options.analysisRootPath,
        'analysisRootPath',
        'must contain $rootPath',
      );
    }

    final discovered = discoverDartFilesSplit(options);
    final files = discovered.candidates;
    _report('Discovered ${files.length} Dart file(s) to scan.');

    if (files.isEmpty) {
      return .new(
        unused: const [],
        docOnly: const [],
        filesScanned: 0,
        declarationsChecked: 0,
        elapsed: stopwatch.elapsed,
      );
    }

    _report('Starting Dart analysis server…');
    final client = await LspClient.start(
      dartExecutable: options.dartExecutable,
    );

    final Settled settled;
    final int declarationsChecked;
    try {
      if (analysisRoot != rootPath) {
        _report(
          'Analyzing within $analysisRoot: references outside the scanned '
          'package count.',
        );
      }
      await client.initialize(Directory(analysisRoot).uri);
      _report('Waiting for initial analysis to complete…');
      await client.waitForAnalysisComplete();

      // Phase 0: open every file first, so the server analyzes them in one
      // pass and keeps them resident. Generated files are opened so references
      // into them resolve, but no candidates are collected from them.
      _report('Opening ${files.length + discovered.warmOnly.length} file(s)…');
      final opened = <String>{
        for (final path in [...discovered.warmOnly, ...files])
          if (_openFile(client, path)) path,
      };

      // Phase 1: collect candidate declarations, concurrently.
      _report('Collecting declarations from ${files.length} file(s)…');
      final perFile = await mapPooled(
        files,
        options.concurrency,
        (path) => opened.contains(path)
            ? _collector.collect(client, path, rootPath)
            : Future.value(const <Candidate>[]),
      );
      final candidates = [for (final list in perFile) ...list];
      declarationsChecked = candidates.length;
      _collector.reportSkipped();

      // Phase 2: check references for every candidate through a single global
      // pool, so the server stays saturated instead of stalling between files.
      _report('Checking references for $declarationsChecked declaration(s)…');
      final refsByCandidate = await _fetch.references(
        client,
        candidates,
        totalFiles: files.length,
        rootPath: rootPath,
      );
      await _fetch.semanticTokensFor(client, refsByCandidate);
      await _fetch.selectionRanges(client, candidates, refsByCandidate);

      // Phase 3: settle the verdicts.
      settled = await _settler.settle(
        client,
        candidates,
        refsByCandidate,
        scannedPaths: files.where(opened.contains).toSet(),
        rootPath: rootPath,
        analysisRoot: analysisRoot,
      );
    } finally {
      await client.dispose();
    }

    stopwatch.stop();
    return .new(
      unused: settled.unused,
      docOnly: settled.docOnly,
      filesScanned: files.length,
      declarationsChecked: declarationsChecked,
      elapsed: stopwatch.elapsed,
      recoveredReferences: settled.recovered,
    );
  }

  /// Opens [path] in the server. `false` if the file cannot be read.
  bool _openFile(LspClient client, String path) {
    final content = SourceIndex.readFile(path);
    if (content == null) {
      return false;
    }
    client.didOpen(File(path).uri, content);
    _sources.cacheLines(path, content.split('\n'));
    return true;
  }
}
