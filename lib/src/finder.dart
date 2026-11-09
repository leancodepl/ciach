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
/// | `workspace/`      | The package on disk: Dart files, pubspecs and package configs.        |
/// | `source/`         | Source text, outlines, markers, and the syntax that the rules read.   |
/// | `analysis/`       | The files as `package:analyzer` reads them; nothing else uses it.     |
/// | `conventions/`    | Framework rules that keep declarations alive: Flutter, freezed, l10n. |
/// | `project_config/` | Entry points and generated files read from the project's own config.  |
/// | `collect/`        | Which declarations get checked.                                       |
/// | `fetch/`          | The references, and what the rules read about the referring code.     |
/// | `settle/`         | Turning references into findings.                                     |
/// | `remove/`         | `--remove`: deleting findings and emptied files.                      |
/// | `report/`         | The output formats.                                                   |
/// | `cli/`            | The command line: options, the config file, the console.              |
/// | `util/`           | Small helpers with no knowledge of ciach.                             |
library;

import 'dart:async';

import 'package:ciach/src/analysis/directives.dart';
import 'package:ciach/src/analysis/discovered_files.dart';
import 'package:ciach/src/analysis/language_versions.dart';
import 'package:ciach/src/analysis/public_api.dart';
import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidate_collector.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/problems.dart';
import 'package:ciach/src/conventions/conditional_imports.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/fetch/reachable_types.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/settle/reference_classifier.dart';
import 'package:ciach/src/settle/settler.dart';
import 'package:ciach/src/settle/verdict.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:ciach/src/workspace/dart_executable.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:ciach/src/workspace/path_dependents.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.finder');

/// Finds declarations that are never referenced.
///
/// `package:analyzer` resolves every file under the analysis root, lists the
/// declarations of each scanned file, and records where each declaration is
/// used. A declaration without uses outside itself is unused.
///
/// `Ciach` owns the analyzer and the pipeline (discover →
/// collect → fetch → settle); each stage is a collaborator: [CandidateCollector] decides
/// what to check, [referencesOf] gets the references, [Settler] turns them
/// into findings with [ReferenceClassifier] deciding used/unused, [Verdict]
/// deciding how a dead candidate is reported, and the `conventions/` rules
/// keeping framework-driven declarations alive.
///
/// A run logs through `package:logging`, with loggers such as `ciach.finder`
/// and `ciach.remover`, and never configures the root logger: listen on
/// `Logger.root.onRecord` to see the records.
class Ciach {
  /// Creates a finder that runs with the given [options].
  Ciach(this.options);

  /// The configuration for this run.
  final FinderOptions options;

  /// Runs the analysis and returns the declarations that are never referenced.
  ///
  /// Throws an [ArgumentError] if [FinderOptions.analysisRootPath] does not
  /// contain [FinderOptions.rootPath]; widening to a directory beside the
  /// scanned one would drop references rather than add them. Throws an
  /// [UnsupportedLanguageVersionException] if a scanned package uses a newer
  /// Dart language version than the analyzer supports.
  Future<FinderResult> run() => _Run(options).run();
}

/// One run of [Ciach], with the state that it builds up.
final class _Run {
  _Run(this.options);

  final FinderOptions options;

  /// The files under the analysis root as the analyzer resolves them, shared
  /// by the classification and the structural detectors. It is set once the
  /// analyzer is set up.
  late final ResolvedFiles _files;

  /// Freezed-union tracking, fed as candidates are collected.
  final _freezed = FreezedUnions();

  late final _classifier = ReferenceClassifier(
    _files,
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
    freezed: _freezed,
    publicApi: _publicApi,
    conditionalImports: _conditionalImports,
  );

  late final _settler = Settler(
    options: options,
    files: _files,
    freezed: _freezed,
    classifier: _classifier,
    verdict: .new(options: options, classifier: _classifier),
  );

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
    if (!dirContains(analysisRoot, rootPath)) {
      throw ArgumentError.value(
        options.analysisRootPath,
        'analysisRootPath',
        'must contain $rootPath',
      );
    }

    final discovered = discoverDartFiles(options);
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
    checkLanguageVersions(files, rootPath);
    if (options.includePublic && options.analysisRootPath == null) {
      _notePathDependents(rootPath);
    }

    final dartExecutable = findDartExecutable(explicit: options.dartExecutable);
    _files = .new(analysisRoot, sdkPath: sdkPathOf(dartExecutable));

    final Settled settled;
    final int declarationsChecked;
    final ({List<String> files, List<String> variants}) empty;
    try {
      if (analysisRoot != rootPath) {
        _log.config(
          'Analyzing within $analysisRoot: references outside the scanned package count.',
        );
      }

      // Phase 1: collect candidate declarations.
      _log.info(
        'Collecting declarations from ${plural(files.length, 'file', 'files')}…',
      );
      final collected = [
        for (final path in files)
          ...await _collector.collect(_files, path, rootPath),
      ];
      _collector.reportSkipped();
      // The files whose declarations were collected.
      final scanned = {for (final path in files) path: ?_files.resolved(path)};
      empty = _emptyFiles(scanned);

      // Phase 2: find the references of every candidate in the files under
      // the analysis root. Generated files are resolved so that the
      // references in them count, but no candidates are collected from them.
      _log.info('Resolving the other files under the analysis root…');
      await _files.resolveAll(discovered.referenceOnly);
      for (final path in discovered.referenceOnly) {
        if (_files.resolved(path) == null) {
          recordIfUnreadable(path);
        }
      }
      final fetched = _references(collected, scanned.keys.toSet());
      final (:candidates, :refsByCandidate) = _conditionalImports.share(
        fetched.candidates,
        fetched.refsByCandidate,
        _collector.declaredInVariants,
        _classifier,
        onDropped: _logDropped,
      );
      declarationsChecked = candidates.length;

      // Phase 3: settle the verdicts; with `transitive`, in rounds.
      settled = _settler.settle(
        candidates,
        refsByCandidate,
        scannedPaths: scanned.keys.toSet(),
        rootPath: rootPath,
      );
    } finally {
      await _files.dispose();
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
      problems: problems.problems,
      emptiedContainers: settled.emptied,
    );
  }

  /// The files of [scanned], by path, that hold nothing but directives and
  /// comments, root-relative, with the conditional-import variants apart.
  /// One another package can import is left out.
  ({List<String> files, List<String> variants}) _emptyFiles(
    Map<String, ResolvedFile> scanned,
  ) {
    final empty = [
      for (final MapEntry(key: path, value: file) in scanned.entries)
        if (isDirectiveOnly(file.content) &&
            !(_publicApi?.isImportable(path) ?? false))
          path,
    ];
    String relative(String path) => relativePosix(path, options.rootPath);
    final files = empty
        .whereNot(_conditionalImports.contains)
        .map(relative)
        .toList();
    final variants = empty
        .where(_conditionalImports.contains)
        .map(relative)
        .toList();
    if (files.length + variants.length case final count && > 0) {
      _log.fine(
        'Found ${plural(count, 'empty file', 'empty files')}: ${[...files, ...variants].join(', ')}.',
      );
    }
    return (files: files, variants: variants);
  }

  void _logDropped(Candidate candidate) => _log.fine(
    'Skipped ${relativePosix(candidate.path, options.rootPath)}:'
    '${candidate.outline.nameRange.start.line + 1} '
    '${candidate.name}: its namesake in another conditional-import '
    'variant is not checked.',
  );

  /// The references of [collected], less the candidates left unchecked.
  /// [scannedPaths] are the files that the candidates were collected from.
  ///
  /// When other packages can import the scanned code, a member of a type
  /// that they can reach is part of its API, so only the members of the
  /// other types are checked.
  ({List<Candidate> candidates, List<List<Location>> refsByCandidate})
  _references(List<Candidate> collected, Set<String> scannedPaths) {
    final api = _publicApi;
    final gated = api == null
        ? const <Candidate>{}
        : collected.where(ReachableTypes.isGated).toSet();
    final fetched = referencesOf(
      _files,
      collected.whereNot(gated.contains).toList(),
    );
    if (api == null || gated.isEmpty) {
      return (candidates: fetched.checked, refsByCandidate: fetched.refs);
    }
    final types = ReachableTypes.find(
      files: _files,
      scannedPaths: scannedPaths,
      api: api,
      candidates: fetched.checked,
      refs: fetched.refs,
    );
    final internal = referencesOf(
      _files,
      gated.where(types.isInternal).toList(),
    );
    return (
      candidates: [...fetched.checked, ...internal.checked],
      refsByCandidate: [...fetched.refs, ...internal.refs],
    );
  }
}
