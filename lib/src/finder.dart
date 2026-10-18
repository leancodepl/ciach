/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

/// A scan as a pipeline: discover the files, collect the candidates, fetch
/// their references, settle the verdicts. [Ciach] wires the stages, and each
/// directory under `lib/src/` holds one part of the work:
///
/// | Directory         | What it holds                                                         |
/// |-------------------|-----------------------------------------------------------------------|
/// | `model/`          | The options a run takes and the findings and results it returns.      |
/// | `workspace/`      | The package on disk: Dart files, pubspecs, directives, public API.    |
/// | `source/`         | Source text and the server's view of it: tokens, shapes, markers.     |
/// | `lsp/`            | The analysis server session and what can go wrong with it.            |
/// | `conventions/`    | Framework rules that keep declarations alive: Flutter, freezed, l10n. |
/// | `project_config/` | Entry points and generated files read from the project's own config.  |
/// | `collect/`        | Which declarations get checked.                                       |
/// | `fetch/`          | Asking the server for references, and for what it misses.             |
/// | `settle/`         | Turning references into findings.                                     |
/// | `remove/`         | `--remove`: deleting findings and emptied files.                      |
/// | `report/`         | The output formats.                                                   |
/// | `cli/`            | The command line: options, the config file, the console.              |
/// | `util/`           | Small helpers with no knowledge of ciach.                             |
library;

import 'dart:async';
import 'dart:io';

import 'package:ciach/src/collect/candidate_collector.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/exposed_types.dart';
import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/fetch/member_probe.dart';
import 'package:ciach/src/fetch/reachable_types.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/settler.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/source/directives.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:ciach/src/workspace/analysis_options.dart';
import 'package:ciach/src/workspace/file_discovery.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:ciach/src/workspace/path_dependents.dart';
import 'package:ciach/src/workspace/public_api.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
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

  /// The candidate files with nothing but directives and comments, as they
  /// are opened.
  final _directiveOnly = <String>[];

  /// Freezed-union tracking, fed as candidates are collected.
  final _freezed = FreezedUnions();

  late final _classifier = ReferenceClassifier(
    _sources,
    unusedUnionMembers: options.unusedUnionMembers,
  );

  /// What other packages can import, when exported declarations are left out.
  late final PublicApi? _publicApi = options.exportedPackages.isEmpty
      ? null
      : _exportedApi();

  /// The variants of the conditional imports under the analysis root.
  late final _conditionalImports = ConditionalImports.scan(
    options.analysisRootPath ?? options.rootPath,
  );

  late final _collector = CandidateCollector(
    options: options,
    sources: _sources,
    freezed: _freezed,
    publicApi: _publicApi,
    conditionalImports: _conditionalImports,
  );

  late final _fetch = ReferenceFetch(options: options, sources: _sources);

  late final _settler = Settler(
    options: options,
    fetch: _fetch,
    conditionalImports: _conditionalImports,
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

  /// Notes, for `-v`, the packages outside [rootPath] that depend on it by
  /// `path:`: their uses are not counted, so what only they use reads as dead.
  /// Not a warning, as scanning a package on its own can be the point; an
  /// explicit --analysis-root, even the package itself, says it is.
  void _notePathDependents(String rootPath) {
    final dependents = pathDependentsOutside(rootPath, rootPath);
    if (dependents.isEmpty) {
      return;
    }
    final common = commonAncestor([rootPath, ...dependents]);
    _log.config(
      'Not counting uses in ${dependents.map(p.relative).join(', ')}, which depend on this package by `path:`: `--analysis-root ${p.relative(common)}` counts them, `--analysis-root ${p.relative(rootPath)}` silences this.',
    );
  }

  /// The API of the packages that [FinderOptions.exportedPackages] match,
  /// each package's verdict logged; `null` when none does.
  PublicApi? _exportedApi() {
    final api = PublicApi.scan(
      options.rootPath,
      exportedPackages: options.exportedPackages,
    );
    for (final MapEntry(key: dir, value: exported) in api.packages.entries) {
      final name = relativePosix(dir, options.rootPath);
      final package = name == '.' ? 'The scanned package' : name;
      _log.config(
        exported
            ? '$package is in `exported-packages`: what other packages can import is left out.'
            : '$package is not in `exported-packages`: its API is checked.',
      );
    }
    return api.isEmpty ? null : api;
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
    for (final path in discovered.ignored) {
      _log.fine(
        'Skipped ${relativePosix(path, rootPath)}: marked `// $ignoreFileMarker`.',
      );
    }

    if (files.isEmpty) {
      return .new(
        unused: const [],
        docOnly: const [],
        filesScanned: 0,
        declarationsChecked: 0,
        elapsed: stopwatch.elapsed,
      );
    }

    // Stop before analysis if a package hasn't had `pub get`: its imports
    // wouldn't resolve, so code it uses would be reported as unused.
    final unresolved = unresolvedPackages(files, rootPath);
    if (unresolved.isNotEmpty) {
      throw UnresolvedPackagesException([
        for (final package in unresolved) relativePosix(package, rootPath),
      ]);
    }
    if (options.includePublic && options.analysisRootPath == null) {
      _notePathDependents(rootPath);
    }

    _log.info('Starting Dart analysis server…');
    final client = await LspClient.start(
      dartExecutable: options.dartExecutable,
    );

    final Settled settled;
    final int declarationsChecked;
    final ({List<String> files, List<String> variants}) empty;
    try {
      if (analysisRoot != rootPath) {
        _log.config(
          'Analyzing within $analysisRoot: references outside the scanned package count.',
        );
      }
      final analysisOptions = analysisOptionsWithoutLints(analysisRoot);
      if (analysisOptions.isNotEmpty) {
        _log.config('Analyzing without lint rules and analyzer plugins.');
      }
      await client.initialize(
        Directory(analysisRoot).uri,
        analysisOptions: analysisOptions,
      );
      _log.info('Waiting for initial analysis to complete…');
      await client.waitForAnalysisComplete();

      // Phase 0: open every file first, so the server analyzes them in one
      // pass and keeps them resident. Generated files are opened so references
      // into them resolve, but no candidates are collected from them.
      _log.info(
        'Opening ${plural(files.length + discovered.warmOnly.length, 'file', 'files')}…',
      );
      final opened = <String>{
        for (final path in discovered.warmOnly)
          if (_openFile(client, path)) path,
        for (final path in files)
          if (_openFile(client, path, checkEmpty: true)) path,
      };
      _openOtherLibraryFiles(client, files, opened);
      empty = _emptyFiles();

      // Phase 1: collect candidate declarations, concurrently.
      _log.info(
        'Collecting declarations from ${plural(files.length, 'file', 'files')}…',
      );
      final exposedTypes = ExposedTypes(client, _sources);
      final perFile = await mapPooled(
        files,
        options.concurrency,
        (path) => opened.contains(path)
            ? _collector.collect(client, exposedTypes, path, rootPath)
            : .value(const <Candidate>[]),
      );
      final collected = [for (final list in perFile) ...list];
      _collector.reportSkipped();

      // Phase 2: check references for every candidate through a single global
      // pool, so the server stays saturated instead of stalling between files.
      final fetched = await _references(
        client,
        collected,
        totalFiles: files.length,
        rootPath: rootPath,
      );
      final withCalls = await _fetch.withImplicitCalls(
        client,
        fetched.candidates,
        fetched.refsByCandidate,
      );
      final (:candidates, :refsByCandidate) = _conditionalImports.share(
        withCalls.checked,
        withCalls.refs,
        _collector.declaredInVariants,
        _classifier,
        onDropped: _logDropped,
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
        probed: fetched.probed,
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
      emptyFiles: empty.files,
      emptyVariants: empty.variants,
      recoveredReferences: settled.recovered,
      problems: problems.problems,
      emptiedContainers: settled.emptied,
    );
  }

  /// The empty candidate files, root-relative, with the conditional-import
  /// variants apart. One another package can import is left out.
  ({List<String> files, List<String> variants}) _emptyFiles() {
    final files = <String>[];
    final variants = <String>[];
    for (final path in _directiveOnly) {
      if (_publicApi?.isImportable(path) ?? false) {
        continue;
      }
      (_conditionalImports.contains(path) ? variants : files).add(
        relativePosix(path, options.rootPath),
      );
    }
    if (files.length + variants.length case final count && > 0) {
      _log.fine(
        'Found ${plural(count, 'empty file', 'empty files')}: ${[...files, ...variants].join(', ')}.',
      );
    }
    return (files: files, variants: variants);
  }

  void _logDropped(Candidate candidate) => _log.fine(
    'Skipped ${relativePosix(candidate.path, options.rootPath)}:'
    '${candidate.symbol.selectionRange.start.line + 1} '
    '${candidate.symbol.name}: its namesake in another conditional-import '
    'variant is not checked.',
  );

  /// The references of [collected], less the candidates left unchecked.
  ///
  /// Members of an unexported type wait until the types' references show
  /// which ones another package can reach; the rest are settled by
  /// [probeMembers] first, and the settling adds their full references to the
  /// uses it found before calling one dead.
  Future<
    ({
      List<Candidate> candidates,
      List<List<Location>> refsByCandidate,
      Set<Candidate> probed,
    })
  >
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
      return (
        candidates: candidates,
        refsByCandidate: refsByCandidate,
        probed: const <Candidate>{},
      );
    }
    final types = await ReachableTypes.find(
      client: client,
      sources: _sources,
      fetch: _fetch,
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
    return (
      candidates: candidates,
      refsByCandidate: refsByCandidate,
      probed: probed.used.toSet(),
    );
  }

  /// Opens the files of the libraries of [files] that aren't [opened]. Their
  /// outlines show which private types of a scanned library a public
  /// declaration exposes.
  void _openOtherLibraryFiles(
    LspClient client,
    List<String> files,
    Set<String> opened,
  ) {
    final packages = PackageResolver();
    final libraries = {for (final path in files) ?libraryOf(path, packages)};
    for (final path in {
      for (final library in libraries) ...filesOfLibrary(library, packages),
    }.difference(opened)) {
      _openFile(client, path);
    }
  }

  /// Opens [path] in the server, noting it in [_directiveOnly] if [checkEmpty]
  /// and it has nothing but directives. `false` if the file cannot be read.
  bool _openFile(LspClient client, String path, {bool checkEmpty = false}) {
    final String content;
    try {
      content = File(path).readAsStringSync();
    } on FileSystemException catch (e) {
      recordProblem(_unreadableFile, e, path: path);
      return false;
    }
    client.didOpen(File(path).uri, content);
    _sources.cacheLines(path, content.split('\n'));
    if (checkEmpty && isDirectiveOnly(content)) {
      _directiveOnly.add(path);
    }
    return true;
  }
}
