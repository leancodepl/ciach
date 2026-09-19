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
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/flutter_widgets.dart';
import 'package:ciach/src/conventions/freezed.dart';
import 'package:ciach/src/conventions/serialization.dart';
import 'package:ciach/src/cross_library_refs.dart';
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/overrides.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_classifier.dart';
import 'package:ciach/src/remove_safety.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/superclasses.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Position, Range, SelectionRange;

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
/// the `conventions/` rules ([EntryPoints], [FreezedUnions], serialization and
/// Flutter widgets) keep framework-driven declarations alive.
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

  late final _entryPoints = EntryPoints(options.entryPoints);

  /// Skipped as entry points this run, for `--verbose`.
  final _skippedEntryPoints = <_SkippedEntryPoint>[];

  /// Types whose member is an entry point, by `(relative path, type name)`:
  /// the generated call that reaches `MyPlugin.registerWith` names `MyPlugin`
  /// too, so the type is not a candidate either.
  final _entryPointContainers = <DeclKey, EntryPoint>{};

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

  static const _primaryConstructorHint =
      'primary constructor — declared in the class header, so it cannot be '
      'removed without removing the class';

  static const _declaringParameterHint =
      'declaring parameter of the primary constructor — removing it changes '
      'the constructor signature at every call site';

  static const _overriddenHint =
      'overridden by a declaration --remove will not delete — that override '
      'would be left overriding nothing';

  void _report(String message) => options.onProgress?.call(message);

  /// Runs the analysis and returns the declarations that are never referenced.
  Future<FinderResult> run() async {
    final stopwatch = Stopwatch()..start();
    final rootPath = options.rootPath;
    final analysisRoot = options.analysisRootPath ?? rootPath;

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
    var recoveredReferences = const <RecoveredReference>[];
    var declarationsChecked = 0;

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
            ? _collectCandidatesFor(client, path, rootPath)
            : Future.value(const <Candidate>[]),
      );
      final candidates = [for (final list in perFile) ...list];
      declarationsChecked = candidates.length;
      _reportSkippedEntryPoints();

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

      await _fetchSemanticTokensFor(client, refsByCandidate);
      await _fetchSelectionRanges(client, candidates, refsByCandidate);

      // Phase 3: a secondary check that confirms apparently-unreferenced
      // members are actually unused before they are reported.
      final crossLib = await _recoverCrossLibraryRefs(
        client,
        candidates,
        refsByCandidate,
      );

      final statuses = [
        for (var i = 0; i < candidates.length; i++)
          _classifier.classify(candidates[i], refsByCandidate[i], crossLib),
      ];

      recoveredReferences = _recoveredWarnings(
        candidates,
        refsByCandidate,
        crossLib,
        rootPath,
        analysisRoot,
      );

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

      final safety = await RemoveSafety.analyze(
        _sources,
        candidates,
        statuses,
        refsByCandidate,
        deadClassNames,
        SuperclassChecks(client).needsConstructorArguments,
      );

      final reported = <int>{
        for (var i = 0; i < candidates.length; i++)
          if (statuses[i] == .unused &&
              !_isSuppressed(
                candidates[i],
                i,
                freezedUnionArms,
                deadClassNames,
                safety,
              ))
            i,
      };

      // Phase 4: couple a dead member's overrides to its removal, or let one
      // that has to stay block it.
      final scannedPaths = files.where(opened.contains).toSet();
      final overridden = await _coupleOverrides(
        client,
        candidates,
        reported,
        scannedPaths,
        rootPath,
      );

      for (var i = 0; i < candidates.length; i++) {
        final candidate = candidates[i];
        final refs = refsByCandidate[i];
        switch (statuses[i]) {
          case .unused:
            if (!reported.contains(i)) {
              break;
            }
            final isClass = candidate.symbol.kind == .class$;
            final overrides = overridden[i];
            final blockedByOverride = overrides?.blocked ?? false;
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
                    : overrides?.removals ?? const [],
                removalBlocked:
                    _isRemovalBlocked(candidate, refs, safety) ||
                    blockedByOverride,
                hint:
                    _hintFor(candidate) ??
                    (blockedByOverride ? _overriddenHint : null),
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
      recoveredReferences: recoveredReferences,
    );
  }

  /// The overrides to delete along with each reported dead member, by
  /// candidate index. Members with nothing to say are left out.
  Future<Map<int, OverriddenMember>> _coupleOverrides(
    LspClient client,
    List<Candidate> candidates,
    Set<int> reported,
    Set<String> scannedPaths,
    String rootPath,
  ) async {
    final members = [
      for (final index in reported)
        if (_canBeOverridden(candidates[index])) index,
    ];
    if (members.isEmpty) {
      return const {};
    }
    _report('Checking ${members.length} dead member(s) for overrides…');
    final overrides = OverrideRemovals(
      client,
      _sources,
      scannedPaths: scannedPaths,
      rootPath: rootPath,
    );
    final results = await mapPooled(
      members,
      options.concurrency,
      (index) => overrides.of(candidates[index]),
    );
    final byCandidate = <int, OverriddenMember>{};
    var coupled = 0;
    var blocked = 0;
    for (var i = 0; i < members.length; i++) {
      final result = results[i];
      if (result.removals.isEmpty && !result.blocked) {
        continue;
      }
      byCandidate[members[i]] = result;
      coupled += result.removals.length;
      if (result.blocked) {
        blocked++;
      }
    }
    if (coupled > 0) {
      _report(
        'Coupling $coupled override(s) to the dead member(s) they implement.',
      );
    }
    if (blocked > 0) {
      _report(
        '$blocked dead member(s) are overridden where --remove cannot '
        'follow; left in place.',
      );
    }
    return byCandidate;
  }

  /// Whether [candidate] is a member a subclass could override. A declaring
  /// parameter is never removed anyway.
  bool _canBeOverridden(Candidate candidate) => switch (candidate.symbol.kind) {
    .method || .property || .field =>
      candidate.container != null &&
          !candidate.isExtensionMember &&
          !_isHeaderDeclaration(candidate),
    _ => false,
  };

  /// One warning per declaration the secondary check kept alive: it had no
  /// reported references, yet a use resolved back to it.
  List<RecoveredReference> _recoveredWarnings(
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    CrossLibraryReferences crossLib,
    String rootPath,
    String analysisRoot,
  ) {
    final warnings = <RecoveredReference>[];
    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      if (refsByCandidate[i].isNotEmpty ||
          candidate.symbol.kind == .class$ ||
          candidate.isExtension) {
        continue;
      }
      final usage = crossLib.recoveredUsage(candidate);
      if (usage == null) {
        continue;
      }
      final start = candidate.symbol.selectionRange.start;
      warnings.add(
        RecoveredReference(
          name: candidate.symbol.declarationName(candidate.container),
          container: candidate.container,
          filePath: relativePosix(candidate.path, rootPath),
          line: start.line + 1,
          column: start.character + 1,
          usageFilePath: relativeUsagePosix(usage.path, rootPath, analysisRoot),
          usageLine: usage.line + 1,
          usageColumn: usage.character + 1,
        ),
      );
    }
    warnings.sort((a, b) {
      final byFile = a.filePath.compareTo(b.filePath);
      if (byFile != 0) {
        return byFile;
      }
      final byLine = a.line.compareTo(b.line);
      return byLine != 0 ? byLine : a.column.compareTo(b.column);
    });
    return warnings;
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
      // The server would answer for an unnamed extension's `on` type.
      final refs = candidate.isUnnamedExtension
          ? const <Location>[]
          : await client.references(
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

  /// Fetches the semantic tokens of every referenced file that has none yet.
  Future<void> _fetchSemanticTokensFor(
    LspClient client,
    List<List<Location>> refsByCandidate,
  ) async {
    final paths = <String>{
      for (final refs in refsByCandidate)
        for (final loc in refs)
          if (!_sources.hasSemanticTokens(SourceIndex.pathOf(loc.uri)))
            SourceIndex.pathOf(loc.uri),
    };
    if (paths.isEmpty) {
      return;
    }
    _report('Fetching tokens for ${paths.length} referenced file(s)…');
    await mapPooled(paths.toList(), options.concurrency, (path) async {
      _sources.cacheSemanticTokens(
        path,
        await _semanticTokensOrEmpty(client, path),
      );
    });
  }

  /// Fetches the selection ranges the structural checks need, one request per
  /// file.
  Future<void> _fetchSelectionRanges(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
  ) async {
    final positionsByPath = <String, Set<Position>>{};
    void add(String path, Position position) =>
        positionsByPath.putIfAbsent(path, () => {}).add(position);

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final kind = candidate.symbol.kind;
      final isEnumType = kind == .enum$ && !candidate.isEnumValue;
      if (isEnumType || kind == .class$) {
        for (final loc in refsByCandidate[i]) {
          add(SourceIndex.pathOf(loc.uri), loc.range.start);
        }
      }
      if ((kind == .constructor || kind == .field) &&
          candidate.containerOutline != null) {
        add(candidate.path, candidate.symbol.selectionRange.start);
      }
      if (isEnumType) {
        for (final token in _sources.valuesTokensIn(candidate)) {
          add(candidate.path, token.start);
        }
      }
      if (kind == .constructor) {
        if (_sources.redirectProbePosition(candidate) case final position?) {
          add(candidate.path, position);
        }
      }
    }
    if (positionsByPath.isEmpty) {
      return;
    }
    _report('Fetching syntax nodes in ${positionsByPath.length} file(s)…');
    await mapPooled(positionsByPath.entries.toList(), options.concurrency, (
      entry,
    ) async {
      final MapEntry(key: path, value: positions) = entry;
      final ordered = positions.toList();
      List<SelectionRange?> ranges;
      try {
        ranges = await client.selectionRanges(File(path).uri, ordered);
      } on Object {
        return; // a position with no answer reads as "not the special shape"
      }
      for (var i = 0; i < ordered.length; i++) {
        if (ranges[i] case final range?) {
          _sources.cacheSelectionRange(path, ordered[i], range);
        }
      }
    });
  }

  /// The semantic tokens of [path], or an empty list if the server has none.
  /// A file without tokens reads as all code, which only keeps declarations.
  Future<List<SemanticToken>> _semanticTokensOrEmpty(
    LspClient client,
    String path,
  ) async {
    try {
      return await client.semanticTokens(File(path).uri, _sources.lines(path));
    } on Object {
      return const [];
    }
  }

  /// Runs the secondary definition check for the candidates whose reference
  /// query came back empty — the potential false positives.
  Future<CrossLibraryReferences> _recoverCrossLibraryRefs(
    LspClient client,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
  ) {
    final emptyRefNames = <String>{
      for (var i = 0; i < candidates.length; i++)
        if (refsByCandidate[i].isEmpty &&
            candidates[i].symbol.kind != .class$ &&
            !candidates[i].isExtension) ...[
          _simpleName(candidates[i].symbol.name),
          // An unnamed constructor is spelled by the class name at an
          // ordinary `Foo(…)` site but as `new` at a dot-shorthand one
          // (`.new(…)`), so probe for both spellings.
          candidates[i].symbol.declarationName(candidates[i].container),
        ],
    };
    if (emptyRefNames.isNotEmpty) {
      _report('Recovering cross-library references…');
    }
    return CrossLibraryReferences.resolve(
      client: client,
      sources: _sources,
      candidates: candidates,
      emptyRefNames: emptyRefNames,
      concurrency: options.concurrency,
    );
  }

  /// The last-segment name — `bar` for a constructor reported as `Foo.bar` —
  /// which is the identifier a usage site spells.
  static String _simpleName(String name) =>
      name.contains('.') ? name.split('.').last : name;

  String? _hintFor(Candidate candidate) {
    if (_isHeaderDeclaration(candidate)) {
      return candidate.symbol.kind == .constructor
          ? _primaryConstructorHint
          : _declaringParameterHint;
    }
    return candidate.isPreventInstantiationCtor
        ? _preventInstantiationHint
        : null;
  }

  /// See [StructuralChecks.isDeclaredInTypeHeader].
  bool _isHeaderDeclaration(Candidate candidate) =>
      switch (candidate.symbol.kind) {
        .constructor || .field => _sources.isDeclaredInTypeHeader(candidate),
        _ => false,
      };

  /// Whether an unused [candidate] should be silently suppressed (never
  /// reported): a live freezed-union arm, an exempt `toJson` hook, a
  /// constructor removed with its already-dead class, an extension or its
  /// members (see [RemoveSafety.deadExtensions]), or an enum value reached
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
    if (!options.reportToJson && isToJsonHook(candidate)) {
      return true;
    }
    if (_isRemovedWithDeadClass(candidate, deadClassNames)) {
      return true;
    }
    // Used through its members, never by name.
    if (candidate.isExtension &&
        !safety.deadExtensions.contains(candidate.key)) {
      return true;
    }
    final containerKey = candidate.containerKey;
    if (containerKey == null) {
      return false;
    }
    if (candidate.isExtensionMember &&
        safety.deadExtensions.contains(containerKey)) {
      return true;
    }
    return candidate.isEnumValue &&
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
  ///   super-constructor forwarding;
  /// * a primary constructor or one of its declaring parameters.
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
            safety.blockedCtorClasses.contains(containerKey)) ||
        _isHeaderDeclaration(candidate);
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

  /// One line per skipped entry point, except the ubiquitous `main`.
  void _reportSkippedEntryPoints() {
    if (options.onProgress == null) {
      return;
    }
    _skippedEntryPoints.sort((a, b) {
      final byFile = a.path.compareTo(b.path);
      return byFile != 0 ? byFile : a.line.compareTo(b.line);
    });
    for (final skipped in _skippedEntryPoints) {
      if (skipped.name == 'main') {
        continue;
      }
      _report(
        'Skipped ${skipped.path}:${skipped.line} ${skipped.name}: '
        '${skipped.reason}.',
      );
    }
  }

  /// The declarations of the open file [path] worth checking.
  Future<List<Candidate>> _collectCandidatesFor(
    LspClient client,
    String path,
    String rootPath,
  ) async {
    final uri = File(path).uri;
    final (symbols, outline, tokens) = await (
      client.documentSymbol(uri),
      client.outline(uri),
      _semanticTokensOrEmpty(client, path),
    ).wait;
    _sources.cacheSemanticTokens(path, tokens);
    final relativePath = relativePosix(path, rootPath);
    final out = <Candidate>[];
    _collectCandidates(
      uri,
      path,
      relativePath,
      symbols,
      null,
      null,
      false,
      _OutlineIndex(outline),
      out,
    );
    return _withoutEntryPointContainers(out, relativePath);
  }

  /// [candidates] less the types a member entry point lives in; see
  /// [_entryPointContainers]. Their other members stay candidates.
  List<Candidate> _withoutEntryPointContainers(
    List<Candidate> candidates,
    String relativePath,
  ) {
    if (_entryPointContainers.isEmpty) {
      return candidates;
    }
    final kept = <Candidate>[];
    for (final candidate in candidates) {
      final symbol = candidate.symbol;
      final rule =
          candidate.container == null && typeLikeKinds.contains(symbol.kind)
          ? _entryPointContainers[DeclKey(relativePath, symbol.name)]
          : null;
      if (rule == null) {
        kept.add(candidate);
        continue;
      }
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: symbol.name,
        reason: 'declares the entry point ${rule.name}',
      ));
    }
    return kept;
  }

  /// Recursively walks the symbol tree, keeping only symbols worth checking,
  /// and records the enclosing type name as their container.
  ///
  /// [parentIsEnum] marks children of an enum declaration so their enum values
  /// are remapped to the `enum-value` kind.
  void _collectCandidates(
    Uri uri,
    String path,
    String relativePath,
    List<DocumentSymbol> symbols,
    String? container,
    Candidate? containerCandidate,
    bool parentIsEnum,
    _OutlineIndex outlines,
    List<Candidate> out,
  ) {
    // A field statement's doc comment, annotations and modifiers sit on its
    // first declarator, so a later one (`b` in `@override final int a, b;`)
    // reads that statement's instead of its own, which are empty.
    var statementMetadata = const <SemanticToken>[];
    for (final symbol in symbols) {
      final outline = outlines[symbol];
      if (outline == null) {
        _report(
          'Skipped $relativePath:${symbol.selectionRange.start.line + 1} '
          "${symbol.name}: the analysis server's outline has no entry for it.",
        );
        continue;
      }
      final ownMetadata = _sources.leadingMetadata(path, outline);
      final isField = outline.element.kind == .field;
      final continuesStatement =
          isField && outline.range.start == outline.codeRange.start;
      final leadingMetadata = continuesStatement
          ? statementMetadata
          : ownMetadata;
      statementMetadata = isField && !continuesStatement
          ? ownMetadata.toList()
          : const [];
      _freezed.noteIfAnnotated(path, symbol, leadingMetadata);
      final candidate = Candidate(
        uri: uri,
        path: path,
        symbol: symbol,
        outline: outline,
        container: container,
        containerSymbol: containerCandidate?.symbol,
        containerOutline: containerCandidate?.outline,
        isEnumValue: parentIsEnum && symbol.kind == .enum$,
        isPreventInstantiationCtor: symbol.isPreventInstantiationMarker(
          symbols,
        ),
      );
      if (_shouldConsider(relativePath, candidate, leadingMetadata)) {
        out.add(candidate);
      }
      final isTypeLike = typeLikeKinds.contains(symbol.kind);
      _collectCandidates(
        uri,
        path,
        relativePath,
        symbol.children ?? const [],
        isTypeLike ? symbol.name : container,
        isTypeLike ? candidate : containerCandidate,
        symbol.kind == .enum$,
        outlines,
        out,
      );
    }
  }

  /// Whether [candidate] should have its references checked.
  bool _shouldConsider(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
  ) {
    final symbol = candidate.symbol;
    final container = candidate.container;
    if (!options.kinds.contains(
      symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
      ),
    )) {
      return false;
    }
    // Called by a framework or tool, with no source reference to find.
    if (_entryPoints.match(relativePath, symbol, container) case final rule?) {
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: rule.name,
        reason: rule.reason,
      ));
      if (container != null) {
        _entryPointContainers.putIfAbsent(
          DeclKey(relativePath, container),
          () => rule,
        );
      }
      return false;
    }
    if (symbol.kind == .namespace &&
        !candidate.isExtension &&
        !candidate.isExtensionType) {
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
    // Already represented by the header's constructor symbol.
    if (symbol.isPrimaryConstructorBody) {
      return false;
    }

    if (options.skipOverrides &&
        leadingMetadata.any((t) => t.isAnnotationNamed('override'))) {
      return false;
    }
    // Symbols reachable from native code / reflection are not really unused.
    if (leadingMetadata.any(
      (t) => t.type == 'string' && t.text.contains('vm:entry-point'),
    )) {
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
    // An unnamed extension's selection range is its `on` type.
    final start = candidate.isUnnamedExtension
        ? symbol.range.start
        : symbol.selectionRange.start;
    final name = symbol.declarationName(candidate.container);
    // `extension on T` is no name to qualify members by.
    final container = _isInUnnamedExtension(candidate)
        ? null
        : candidate.container;
    return .new(
      name: name,
      kind: symbol.reportedKind(
        parentIsEnum: candidate.isEnumValue,
        isExtensionType: candidate.isExtensionType,
      ),
      filePath: relativePosix(candidate.path, rootPath),
      // LSP positions are zero-based; report them one-based for humans.
      line: start.line + 1,
      column: start.character + 1,
      isPrivate: isPrivateName(name),
      container: container,
      isEnumValue: candidate.isEnumValue,
      range: symbol.declarationRange,
      fullRange: candidate.outline.range.toDeclarationRange,
      coupledRemovals: coupledRemovals,
      removalBlocked: removalBlocked,
      hint: hint,
    );
  }

  bool _isInUnnamedExtension(Candidate candidate) =>
      candidate.containerOutline?.element.isUnnamedExtension ?? false;

  /// Whether [candidate] goes with an already-dead class's own declaration —
  /// any constructor, or a declaring parameter — so a single removal is not
  /// reported twice.
  bool _isRemovedWithDeadClass(
    Candidate candidate,
    Map<String, Set<String>> deadClassNames,
  ) =>
      (candidate.symbol.kind == .constructor ||
          _isHeaderDeclaration(candidate)) &&
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

/// A skipped entry point: root-relative POSIX path, one-based line, the name
/// as the rule spells it, and why.
typedef _SkippedEntryPoint = ({
  String path,
  int line,
  String name,
  String reason,
});

/// Outline nodes by document symbol: a symbol's `range` is its node's
/// `codeRange`.
final class _OutlineIndex {
  _OutlineIndex(Outline root)
    : _byCodeRange = {
        for (final node in root.descendants) _key(node.codeRange): node,
      };

  final Map<_RangeKey, Outline> _byCodeRange;

  Outline? operator [](DocumentSymbol symbol) =>
      _byCodeRange[_key(symbol.range)];

  static _RangeKey _key(Range range) => (
    range.start.line,
    range.start.character,
    range.end.line,
    range.end.character,
  );
}

typedef _RangeKey = (int, int, int, int);
