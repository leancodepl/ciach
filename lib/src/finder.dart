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

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/conventions/serialization.dart';
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// Finds declarations that are never referenced by driving the Dart analysis
/// server over LSP.
///
/// For every declaration reported by `textDocument/documentSymbol`, a
/// `textDocument/references` query is issued at the declaration's name, with
/// `includeDeclaration: false`. An empty result means the declaration is unused.
///
/// `Ciach` owns the pipeline (discover → collect → check references → report);
/// the semantic pieces live in collaborators: [ReferenceClassifier] decides
/// used/unused, [RemoveSafety] flags findings that can't be auto-removed, and
/// the `conventions/` rules ([FreezedUnions], serialization and Flutter
/// widgets) keep framework-driven declarations alive.
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

  /// Advisory note attached to a sole, zero-parameter private constructor
  /// (`Foo._();`) — the classic prevent-instantiation marker. Such a
  /// constructor is still reported (and removable) like any other dead code,
  /// but the note points at the idiomatic alternative.
  static const _preventInstantiationHint =
      'looks like a prevent-instantiation constructor — for a '
      'non-instantiable static-only class, prefer `abstract final class`';

  void _report(String message) => options.onProgress?.call(message);

  /// Runs the analysis and returns the declarations that are never referenced.
  Future<FinderResult> run() async {
    final stopwatch = Stopwatch()..start();
    final rootPath = p.normalize(p.absolute(options.rootPath));

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

    final unused = <UnusedDeclaration>[];
    final docOnly = <UnusedDeclaration>[];
    var declarationsChecked = 0;

    try {
      await client.initialize(Directory(rootPath).uri);
      _report('Waiting for initial analysis to complete…');
      await client.waitForAnalysisComplete();

      // Phase 0: open the excluded generated files (without collecting them as
      // candidates) so a reference query for a declaration used *only* from
      // generated code — e.g. a `toJson` called from a `.g.dart` — resolves.
      if (discovered.warmOnly.isNotEmpty) {
        _report('Warming ${discovered.warmOnly.length} generated file(s)…');
        await mapPooled(
          discovered.warmOnly,
          options.concurrency,
          (path) => _warmFile(client, path),
        );
      }

      // Phase 1: open every file and collect its candidate declarations,
      // concurrently. Opening keeps each file's resolved unit warm in the
      // server's cache; without it, reference queries against files the server
      // has evicted come back empty and produce false "unused" reports.
      _report('Collecting declarations from ${files.length} file(s)…');
      final perFile = await mapPooled(
        files,
        options.concurrency,
        (path) => _collectCandidatesFor(client, path),
      );
      final candidates = [for (final list in perFile) ...list];
      declarationsChecked = candidates.length;

      // Phase 2: check references for every candidate through a single global
      // pool, so the server stays saturated instead of stalling between files.
      // Progress is reported per file: each file's remaining count is tracked
      // and a line is emitted as soon as its last declaration is checked. Files
      // with no candidates are already counted as done.
      _report('Checking references for $declarationsChecked declaration(s)…');
      final refsByCandidate = await _checkReferences(
        client,
        candidates,
        files.length,
        rootPath,
      );

      final statuses = [
        for (var i = 0; i < candidates.length; i++)
          _classifier.classify(candidates[i], refsByCandidate[i]),
      ];

      // A deser-only union arm reads zero references but is a live serialization
      // member.
      final freezedUnionArms = _freezed.deserializationOnlyArms(
        candidates,
        statuses,
        _sources,
      );

      // Names of classes flagged unused, per file. A whole dead class is
      // removed as one node, taking its own constructor(s) with it, so those
      // constructors must not also be reported (or removed) on their own.
      final deadClassNames = <String, Set<String>>{};
      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        if (statuses[i] == .unused && candidate.symbol.kind == .class$) {
          deadClassNames
              .putIfAbsent(candidate.path, () => <String>{})
              .add(candidate.symbol.name);
        }
      }

      final safety = RemoveSafety.analyze(
        _sources,
        candidates,
        statuses,
        refsByCandidate,
        deadClassNames,
      );

      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        final refs = refsByCandidate[i];
        switch (statuses[i]) {
          case .unused:
            if (_isSuppressed(
              candidate,
              i,
              freezedUnionArms,
              deadClassNames,
              safety,
            )) {
              break;
            }
            final isClass = candidate.symbol.kind == .class$;
            unused.add(
              _toUnused(
                candidate,
                rootPath,
                coupledRemovals: isClass
                    ? _sources.pairedStateRemovals(
                        candidate,
                        refs,
                        candidates,
                        refsByCandidate,
                        rootPath,
                      )
                    : const [],
                removalBlocked: _isRemovalBlocked(candidate, refs, safety),
                // A sole, zero-parameter private constructor is dead code like
                // any other, but nudge toward `abstract final class`.
                hint: candidate.isPreventInstantiationCtor
                    ? _preventInstantiationHint
                    : null,
              ),
            );
          case .docOnly:
            docOnly.add(_toUnused(candidate, rootPath));
          case .used:
            break;
        }
      }
    } finally {
      await client.dispose();
    }

    unused.sort(_byLocation);
    docOnly.sort(_byLocation);
    stopwatch.stop();
    return .new(
      unused: unused,
      docOnly: docOnly,
      filesScanned: files.length,
      declarationsChecked: declarationsChecked,
      elapsed: stopwatch.elapsed,
    );
  }

  /// Queries `textDocument/references` for every candidate through one global
  /// pool, reporting `[done/total]` progress as each file's last query lands.
  Future<List<List<Location>>> _checkReferences(
    LspClient client,
    List<Candidate> candidates,
    int totalFiles,
    String rootPath,
  ) {
    final remainingPerFile = <String, int>{};
    for (final candidate in candidates) {
      remainingPerFile.update(candidate.path, (n) => n + 1, ifAbsent: () => 1);
    }
    var filesDone = totalFiles - remainingPerFile.length;

    return mapPooled(candidates, options.concurrency, (candidate) async {
      final refs = await client.references(
        candidate.uri,
        candidate.symbol.selectionRange.start,
      );
      if (remainingPerFile.update(candidate.path, (n) => n - 1) == 0) {
        filesDone++;
        _report(
          '[$filesDone/$totalFiles] '
          '${p.relative(candidate.path, from: rootPath)}',
        );
      }
      return refs;
    });
  }

  /// Whether an unused [candidate] should be silently suppressed (never
  /// reported): a live freezed-union arm, an exempt `toJson` hook, a
  /// constructor removed with its already-dead class, or an enum value reached
  /// only through `.values` iteration.
  bool _isSuppressed(
    Candidate candidate,
    int index,
    Set<int> freezedUnionArms,
    Map<String, Set<String>> deadClassNames,
    RemoveSafety safety,
  ) {
    if (freezedUnionArms.contains(index)) {
      return true;
    }
    if (!options.reportToJson && _sources.isToJsonHook(candidate)) {
      return true;
    }
    if (_isConstructorOfDeadClass(candidate, deadClassNames)) {
      return true;
    }
    final containerKey = candidate.containerKey;
    return candidate.isEnumValue &&
        containerKey != null &&
        safety.enumValuesIterated.contains(containerKey);
  }

  /// Whether a dead [candidate] is real but must *not* be auto-removed, because
  /// doing so would break the build:
  ///
  /// * a class kept dead only by type patterns under `--unused-union-members`
  ///   (never constructed, only matched): deleting a sealed member and its
  ///   scattered `case`s is a source rewrite this tool won't attempt;
  /// * an enum value whose removal would empty a still-referenced enum;
  /// * the last constructor of a live class with `final` fields or
  ///   super-constructor forwarding.
  ///
  /// Each is surfaced so a human can act on it, but the remover leaves it — and
  /// anything coupled to it — entirely alone.
  bool _isRemovalBlocked(
    Candidate candidate,
    List<Location> refs,
    RemoveSafety safety,
  ) {
    final containerKey = candidate.containerKey;
    return (candidate.symbol.kind == .class$ &&
            options.unusedUnionMembers &&
            _classifier.isPatternMatchedClass(candidate, refs)) ||
        (candidate.isEnumValue &&
            containerKey != null &&
            safety.emptiedEnums.contains(containerKey)) ||
        (candidate.symbol.kind == .constructor &&
            containerKey != null &&
            safety.blockedCtorClasses.contains(containerKey));
  }

  /// Opens [path] in the analysis server without collecting candidates from
  /// it, so references *into* still-scanned code from this file resolve.
  /// Returns whether the file could be read and opened.
  Future<bool> _warmFile(LspClient client, String path) async {
    final content = SourceIndex.readFile(path);
    if (content == null) {
      return false;
    }
    client.didOpen(File(path).uri, content);
    _sources.cacheLines(path, content.split('\n'));
    return true;
  }

  /// Fetches the symbols for [path] and returns the declarations worth checking.
  Future<List<Candidate>> _collectCandidatesFor(
    LspClient client,
    String path,
  ) async {
    final content = SourceIndex.readFile(path);
    if (content == null) {
      return const [];
    }
    final uri = File(path).uri;
    client.didOpen(uri, content);
    final symbols = await client.documentSymbol(uri);
    _sources.cacheLines(path, content.split('\n'));
    final out = <Candidate>[];
    _collectCandidates(
      uri,
      path,
      symbols,
      null,
      false,
      _sources.lines(path),
      out,
    );
    return out;
  }

  /// Recursively walks the symbol tree, keeping only symbols worth checking,
  /// and records the enclosing type name as their container.
  ///
  /// [parentIsEnum] marks children of an enum declaration so their enum values
  /// are remapped to the `enum-value` kind.
  void _collectCandidates(
    Uri uri,
    String path,
    List<DocumentSymbol> symbols,
    String? container,
    bool parentIsEnum,
    List<String> lines,
    List<Candidate> out,
  ) {
    for (final symbol in symbols) {
      _freezed.noteIfAnnotated(path, symbol, lines);
      if (_shouldConsider(symbol, parentIsEnum, lines)) {
        out.add(
          Candidate(
            uri: uri,
            path: path,
            symbol: symbol,
            container: container,
            isEnumValue: parentIsEnum && symbol.kind == .enum$,
            // `symbols` are this symbol's siblings (its class's members when
            // `symbol` is a constructor), so this confirms the sole-constructor
            // shape without threading the list any further.
            isPreventInstantiationCtor: symbol.isPreventInstantiationMarker(
              symbols,
            ),
          ),
        );
      }
      final childContainer = typeLikeKinds.contains(symbol.kind)
          ? symbol.name
          : container;
      _collectCandidates(
        uri,
        path,
        symbol.children ?? const [],
        childContainer,
        symbol.kind == .enum$,
        lines,
        out,
      );
    }
  }

  bool _shouldConsider(
    DocumentSymbol symbol,
    bool parentIsEnum,
    List<String> lines,
  ) {
    if (!options.kinds.contains(
      symbol.reportedKind(parentIsEnum: parentIsEnum),
    )) {
      return false;
    }
    // The program entry point is never "unused".
    if (symbol.kind == .function && symbol.name == 'main') {
      return false;
    }
    if (!isPrivateName(symbol.name) && !options.includePublic) {
      return false;
    }
    if (options.skipOperators && symbol.isOperator) {
      return false;
    }
    // Always skipped (no flag): implicit-call syntax is unresolvable, like
    // operators.
    if (symbol.isCallMethod) {
      return false;
    }

    final leading = symbol.leadingMetadata(lines);
    if (options.skipOverrides && leading.contains('@override')) {
      return false;
    }
    // Symbols reachable from native code / reflection are not really unused.
    if (leading.contains('vm:entry-point')) {
      return false;
    }
    return true;
  }

  UnusedDeclaration _toUnused(
    Candidate candidate,
    String rootPath, {
    List<CoupledRemoval> coupledRemovals = const [],
    bool removalBlocked = false,
    String? hint,
  }) {
    final symbol = candidate.symbol;
    final start = symbol.selectionRange.start;
    final name = symbol.declarationName(candidate.container);
    return .new(
      name: name,
      kind: symbol.reportedKind(parentIsEnum: candidate.isEnumValue),
      filePath: relativePosix(candidate.path, rootPath),
      // LSP positions are zero-based; report them one-based for humans.
      line: start.line + 1,
      column: start.character + 1,
      isPrivate: isPrivateName(name),
      container: candidate.container,
      isEnumValue: candidate.isEnumValue,
      range: symbol.declarationRange,
      coupledRemovals: coupledRemovals,
      removalBlocked: removalBlocked,
      hint: hint,
    );
  }

  bool _isConstructorOfDeadClass(
    Candidate candidate,
    Map<String, Set<String>> deadClassNames,
  ) =>
      candidate.symbol.kind == .constructor &&
      (deadClassNames[candidate.path]?.contains(candidate.container) ?? false);

  static int _byLocation(UnusedDeclaration a, UnusedDeclaration b) {
    final byFile = a.filePath.compareTo(b.filePath);
    if (byFile != 0) {
      return byFile;
    }
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  }
}
