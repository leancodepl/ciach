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
import 'package:ciach/src/log.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/member_probe.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/problems.dart';
import 'package:ciach/src/public_api.dart';
import 'package:ciach/src/reachable_types.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/settler.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/verdict.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location;

final _log = Logger('ciach.finder');

const _unreadableFile = 'Could not read these files; skipped.';

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

  /// What other packages can import, when exported declarations are left out.
  late final PublicApi? _publicApi = options.includeExported
      ? null
      : .scan(options.rootPath);

  late final _collector = CandidateCollector(
    options: options,
    sources: _sources,
    freezed: _freezed,
    publicApi: _publicApi,
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

  /// Runs the analysis and returns the declarations that are never referenced.
  ///
  /// Throws an [ArgumentError] if [FinderOptions.analysisRootPath] does not
  /// contain [FinderOptions.rootPath]; widening to a directory beside the
  /// scanned one would drop references rather than add them.
  Future<FinderResult> run() {
    final problems = ProblemCollector(options.rootPath);
    return problems.collect(() => _run(problems));
  }

  Future<FinderResult> _run(ProblemCollector problems) async {
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
    _log.info(
      'Discovered ${plural(files.length, 'Dart file', 'Dart files')} to scan.',
    );

    if (files.isEmpty) {
      return .new(
        unused: const [],
        docOnly: const [],
        filesScanned: 0,
        declarationsChecked: 0,
        elapsed: stopwatch.elapsed,
      );
    }

    _log.info('Starting Dart analysis server…');
    final client = await LspClient.start(
      dartExecutable: options.dartExecutable,
    );

    final Settled settled;
    final int declarationsChecked;
    try {
      if (analysisRoot != rootPath) {
        _log.config(
          'Analyzing within $analysisRoot: references outside the scanned '
          'package count.',
        );
      }
      await client.initialize(Directory(analysisRoot).uri);
      _log.info('Waiting for initial analysis to complete…');
      await client.waitForAnalysisComplete();

      // Phase 0: open every file first, so the server analyzes them in one
      // pass and keeps them resident. Generated files are opened so references
      // into them resolve, but no candidates are collected from them.
      _log.info(
        'Opening ${plural(files.length + discovered.warmOnly.length, 'file', 'files')}…',
      );
      final opened = <String>{
        for (final path in [...discovered.warmOnly, ...files])
          if (_openFile(client, path)) path,
      };

      // Phase 1: collect candidate declarations, concurrently.
      _log.info(
        'Collecting declarations from ${plural(files.length, 'file', 'files')}…',
      );
      final perFile = await mapPooled(
        files,
        options.concurrency,
        (path) => opened.contains(path)
            ? _collector.collect(client, path, rootPath)
            : .value(const <Candidate>[]),
      );
      final collected = [for (final list in perFile) ...list];
      _collector.reportSkipped();

      // Phase 2: check references for every candidate through a single global
      // pool, so the server stays saturated instead of stalling between files.
      final (:candidates, :refsByCandidate) = await _references(
        client,
        collected,
        totalFiles: files.length,
        rootPath: rootPath,
      );
      declarationsChecked = candidates.length;
      await _fetch.selectionRanges(client, candidates, refsByCandidate);

      // Phase 3: settle the verdicts; with `transitive`, in rounds.
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
      problems: problems.problems,
    );
  }

  /// The references of [collected], less the candidates left unchecked.
  ///
  /// Members of an unexported type wait until the types' references show
  /// which ones another package can reach; the rest are settled by
  /// [probeMembers] first.
  Future<({List<Candidate> candidates, List<List<Location>> refsByCandidate})>
  _references(
    LspClient client,
    List<Candidate> collected, {
    required int totalFiles,
    required String rootPath,
  }) async {
    final api = _publicApi;
    final gated = api == null
        ? const <Candidate>{}
        : collected.where(ReachableTypes.isGated).toSet();
    final candidates = <Candidate>[];
    final refsByCandidate = <List<Location>>[];
    Future<void> fetch(List<Candidate> batch, int files) async {
      _log.info(
        'Checking references for ${plural(batch.length, 'declaration', 'declarations')}…',
      );
      final fetched = await _fetch.references(
        client,
        batch,
        totalFiles: files,
        rootPath: rootPath,
      );
      await _fetch.semanticTokensFor(client, fetched.refs);
      candidates.addAll(fetched.checked);
      refsByCandidate.addAll(fetched.refs);
    }

    await fetch(collected.whereNot(gated.contains).toList(), totalFiles);
    if (api == null || gated.isEmpty) {
      return (candidates: candidates, refsByCandidate: refsByCandidate);
    }
    final types = await ReachableTypes.find(
      client: client,
      sources: _sources,
      api: api,
      candidates: candidates,
      refs: refsByCandidate,
    );
    final internal = gated.where(types.isInternal).toList();
    _log.info(
      'Looking up uses of ${plural(internal.length, 'member', 'members')} of unexported types…',
    );
    final probed = await probeMembers(
      client: client,
      sources: _sources,
      types: types,
      members: internal,
      concurrency: options.concurrency,
    );
    candidates.addAll(probed.used);
    refsByCandidate.addAll(probed.refs);
    await fetch(probed.rest, probed.rest.map((c) => c.path).toSet().length);
    return (candidates: candidates, refsByCandidate: refsByCandidate);
  }

  /// Opens [path] in the server. `false` if the file cannot be read.
  bool _openFile(LspClient client, String path) {
    final String content;
    try {
      content = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      recordProblem(_unreadableFile, e, path: path);
      return false;
    }
    client.didOpen(File(path).uri, content);
    _sources.cacheLines(path, content.split('\n'));
    return true;
  }
}
