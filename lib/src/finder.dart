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
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/syntax_rules.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// Finds declarations that are never referenced by driving the Dart analysis
/// server over LSP.
///
/// For every declaration reported by `textDocument/documentSymbol`, a
/// `textDocument/references` query is issued at the declaration's name, with
/// `includeDeclaration: false`. An empty result means the declaration is unused.
class Ciach {
  /// Creates a finder that runs with the given [options].
  Ciach(this.options);

  /// The configuration for this run.
  final FinderOptions options;

  /// Lazily-cached source text and tokens for every file touched this run,
  /// shared by the classification and the structural detectors.
  final _sources = SourceIndex();

  /// Keys `(path, class name)` of classes annotated `@freezed`/`@Freezed`.
  final _freezedAnnotatedClasses = <DeclKey>{};

  static final _freezedAnnotation = RegExp(r'@(?:freezed|Freezed)\b');

  /// A JSON-value return type on a `toJson`'s declaration line, before the name.
  static final _toJsonJsonReturn = RegExp(
    r'\b(?:Map|List|String|int|double|num|bool|Object|dynamic)\b\s*(?:<[^;{]*>)?\s*\??\s*$',
  );

  /// The `State<` immediately preceding a type argument, with a token boundary
  /// before `State` so `MyState<…>`/`FooState<…>` don't match.
  static final _statePrefix = RegExp(r'(?:^|[^A-Za-z0-9_$])State<\s*$');

  /// The `>` that closes a single `State<…>` type argument.
  static final _stateSuffix = RegExp(r'^\s*>');

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
      final remainingPerFile = <String, int>{};
      for (final candidate in candidates) {
        remainingPerFile.update(
          candidate.path,
          (n) => n + 1,
          ifAbsent: () => 1,
        );
      }
      final totalFiles = files.length;
      var filesDone = totalFiles - remainingPerFile.length;

      final refsByCandidate = await mapPooled(candidates, options.concurrency, (
        candidate,
      ) async {
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

      final statuses = [
        for (var i = 0; i < candidates.length; i++)
          _classify(candidates[i], refsByCandidate[i]),
      ];

      // A deser-only union arm reads zero references but is a live serialization member.
      final freezedUnionArms = _freezedDeserializedUnionArms(
        candidates,
        statuses,
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

      final safety = _RemoveSafety.analyze(
        this,
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
            if (freezedUnionArms.contains(i)) {
              break;
            }
            if (!options.reportToJson && _isToJsonHook(candidate)) {
              break;
            }
            if (_isConstructorOfDeadClass(candidate, deadClassNames)) {
              break;
            }
            final containerKey = candidate.containerKey;
            // An enum value reached only through `.values` iteration is used,
            // not dead: suppress it entirely (never reported) rather than
            // flagging it for the empty-enum guard.
            if (candidate.isEnumValue &&
                containerKey != null &&
                safety.enumValuesIterated.contains(containerKey)) {
              break;
            }
            final isClass = candidate.symbol.kind == .class$;
            final paired = isClass
                ? _pairedStateRemovals(
                    candidate,
                    refs,
                    candidates,
                    refsByCandidate,
                    rootPath,
                  )
                : const <CoupledRemoval>[];
            // A finding is report-only (removalBlocked) when auto-removing it
            // would break the build:
            //
            // * a class kept dead only by type patterns under
            //   --unused-union-members (never constructed, only matched):
            //   deleting a sealed member and its scattered `case`s is a source
            //   rewrite this tool won't attempt;
            // * an enum value whose removal would empty a still-referenced enum;
            // * the last constructor of a live class with `final` fields or
            //   super-constructor forwarding.
            //
            // Each is surfaced so a human can act on it, but the remover leaves
            // it — and anything coupled to it — entirely alone.
            final removalBlocked =
                (isClass &&
                    options.unusedUnionMembers &&
                    _isPatternMatchedClass(candidate, refs)) ||
                (candidate.isEnumValue &&
                    containerKey != null &&
                    safety.emptiedEnums.contains(containerKey)) ||
                (candidate.symbol.kind == .constructor &&
                    containerKey != null &&
                    safety.blockedCtorClasses.contains(containerKey));
            unused.add(
              _toUnused(
                candidate,
                rootPath,
                coupledRemovals: paired,
                removalBlocked: removalBlocked,
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
      if (typeLikeKinds.contains(symbol.kind) &&
          _freezedAnnotation.hasMatch(symbol.leadingMetadata(lines))) {
        _freezedAnnotatedClasses.add(DeclKey(path, symbol.name));
      }
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
      filePath: _relPath(candidate.path, rootPath),
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

  /// Classifies a candidate from the references reported for it.
  ///
  /// Non-class candidates keep the simple rule: any real (non-doc) reference
  /// means used, only doc-comment links means doc-only, none means unused.
  ///
  /// Classes get [_classifyClass], which discounts *self-references* — the
  /// class's own body, and the `State<Self>` StatefulWidget pairing — so a
  /// class kept alive only by its own unnamed constructor's declaration (whose
  /// name coincides with the class) is correctly seen as dead.
  RefStatus _classify(Candidate candidate, List<Location> refs) {
    if (candidate.symbol.kind == .class$) {
      return _classifyClass(candidate, refs);
    }
    if (refs.isEmpty) {
      return .unused;
    }
    return refs.any((loc) => !_isDocReference(loc)) ? .used : .docOnly;
  }

  /// Classifies a class by its references, ignoring self-references.
  ///
  /// A class is used only if some reference is a real (non-doc) reference from
  /// *outside* the class itself; if the only outside references are doc-comment
  /// links it is doc-only, and otherwise (only self-references, or none at all)
  /// it is unused. This is deliberately conservative: any single unexplained
  /// outside reference keeps the class alive, so the failure mode is missing a
  /// dead class, never deleting a live one.
  RefStatus _classifyClass(Candidate candidate, List<Location> refs) {
    var hasExternalDoc = false;
    var hasPatternMatch = false;
    for (final loc in refs) {
      if (_isSelfClassReference(candidate, loc)) {
        continue;
      }
      if (_isDocReference(loc)) {
        hasExternalDoc = true;
        continue;
      }
      // With --unused-union-members, a reference that is confidently a *type
      // pattern* (a `case`/if-case/while-case pattern, or a switch-expression
      // arm) is a *match*, not a construction: if the type is never
      // constructed, no such match can ever fire, so it is discounted like a
      // self-reference. Any reference that is not confidently a type pattern
      // keeps the class alive — the conservative choice (nested sub-patterns
      // and pattern-variable declarations are intentionally not recognized).
      if (options.unusedUnionMembers && _sources.isPatternRef(loc)) {
        hasPatternMatch = true;
        continue;
      }
      // A real, non-pattern reference from outside: the class is used.
      return .used;
    }
    // Matched-only-by-a-pattern (never constructed) is dead code, not a softer
    // doc-only report.
    if (hasPatternMatch) {
      return .unused;
    }
    return hasExternalDoc ? .docOnly : .unused;
  }

  /// Whether [location] points at a dartdoc `[Xxx]`-style reference rather than
  /// real code — i.e. its line, in the file it points into, starts with `///`.
  /// Block (`/** */`) doc comments aren't recognized; `///` is the standard and
  /// lint-enforced style.
  bool _isDocReference(Location location) {
    final lines = _sources.lines(SourceIndex.pathOf(location.uri));
    final line = location.range.start.line;
    if (line < 0 || line >= lines.length) {
      return false;
    }
    return lines[line].trim().startsWith('///');
  }

  /// Whether [loc] is a reference to [candidate] that does not count as a use.
  ///
  /// Two shapes qualify:
  ///
  /// 1. A reference inside the class's own source span — its body, signature,
  ///    or leading doc/annotation lines. This covers the unnamed constructor's
  ///    declaration, a `State<Foo>` return type on the widget's own
  ///    `createState`, and any purely-internal self-use.
  /// 2. A `State<Foo>` type-argument reference anywhere — the StatefulWidget
  ///    pairing. `State<Foo>` can only ever denote the state object of the
  ///    `Foo` widget, so it never means `Foo` itself is used elsewhere.
  bool _isSelfClassReference(Candidate candidate, Location loc) {
    if (SourceIndex.pathOf(loc.uri) == candidate.path) {
      final top = candidate.symbol.metadataTopLine(
        _sources.lines(candidate.path),
      );
      final pos = loc.range.start;
      if (pos.line >= top && pos.atOrBefore(candidate.symbol.range.end)) {
        return true;
      }
    }
    return _isStatePairingReference(candidate.symbol.name, loc);
  }

  /// Whether [loc] is the class name [className] appearing as the sole type
  /// argument of `State<…>`, e.g. `class _FooState extends State<Foo>`.
  bool _isStatePairingReference(String className, Location loc) {
    final start = loc.range.start;
    final end = loc.range.end;
    if (start.line != end.line) {
      return false;
    }
    final lines = _sources.lines(SourceIndex.pathOf(loc.uri));
    if (start.line < 0 || start.line >= lines.length) {
      return false;
    }
    final line = lines[start.line];
    if (start.character < 0 ||
        end.character > line.length ||
        start.character > end.character) {
      return false;
    }
    if (line.substring(start.character, end.character) != className) {
      return false;
    }
    return _statePrefix.hasMatch(line.substring(0, start.character)) &&
        _stateSuffix.hasMatch(line.substring(end.character));
  }

  bool _isConstructorOfDeadClass(
    Candidate candidate,
    Map<String, Set<String>> deadClassNames,
  ) =>
      candidate.symbol.kind == .constructor &&
      (deadClassNames[candidate.path]?.contains(candidate.container) ?? false);

  /// Whether [candidate] is a `toJson()` serialization hook — a zero-required-arg
  /// method named `toJson` returning any JSON value (`Map`/`List`/`String`/`num`/
  /// `int`/`double`/`bool`, or `Object`/`dynamic`). `jsonEncode(obj)` dispatches to
  /// it dynamically with no source-level `.toJson()` token, so the reference search
  /// can't see that use; exempt it for any class, annotated or not.
  bool _isToJsonHook(Candidate candidate) {
    final symbol = candidate.symbol;
    if (symbol.kind != .method ||
        symbol.name != 'toJson' ||
        !symbol.hasNoParameters) {
      return false;
    }
    final lines = _sources.lines(candidate.path);
    final line = symbol.selectionRange.start.line;
    if (line < 0 || line >= lines.length) {
      return false;
    }
    final col = symbol.selectionRange.start.character;
    final text = lines[line];
    final beforeName = col <= text.length ? text.substring(0, col) : text;
    return _toJsonJsonReturn.hasMatch(beforeName);
  }

  /// Redirecting-factory arms of a `@freezed`/`@Freezed` union with a referenced
  /// `fromJson`; conservative — never-dispatched arms are kept too, being
  /// statically indistinguishable.
  Set<int> _freezedDeserializedUnionArms(
    List<Candidate> candidates,
    List<RefStatus> statuses,
  ) {
    final unionsWithUsedFromJson = <DeclKey>{};
    for (var i = 0; i < candidates.length; i++) {
      final c = candidates[i];
      if (c.symbol.kind == .constructor &&
          statuses[i] == .used &&
          c.symbol.declarationName(c.container) == 'fromJson') {
        if (c.containerKey case final key?) {
          unionsWithUsedFromJson.add(key);
        }
      }
    }

    final arms = <int>{};
    for (var i = 0; i < candidates.length; i++) {
      if (statuses[i] != .unused) {
        continue;
      }
      final c = candidates[i];
      if (c.symbol.kind != .constructor) {
        continue;
      }
      if (c.containerKey case final key?
          when _freezedAnnotatedClasses.contains(key) &&
              unionsWithUsedFromJson.contains(key) &&
              _sources.isRedirectingFactory(c)) {
        arms.add(i);
      }
    }
    return arms;
  }

  /// The extra spans to remove alongside a dead [widget] class: the paired
  /// private `State<Widget>` subclass, when there is exactly one and it is used
  /// only from within the widget (via `createState`). Returns an empty list for
  /// a plain class, or a StatefulWidget whose State is referenced elsewhere.
  ///
  /// Removing the widget on its own would leave
  /// `class _S extends State<Widget>` referring to a now-deleted type — a build
  /// break — so the State is coupled to the widget's removal, but it is not
  /// itself reported.
  List<CoupledRemoval> _pairedStateRemovals(
    Candidate widget,
    List<Location> widgetRefs,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final out = <CoupledRemoval>[];
    for (final loc in widgetRefs) {
      if (!_isStatePairingReference(widget.symbol.name, loc) ||
          SourceIndex.pathOf(loc.uri) != widget.path) {
        continue;
      }
      // The widget's own `createState` return type is inside the widget and
      // removed with it; only a pairing reference outside the widget points at
      // the separate State subclass.
      if (loc.range.start.within(widget.symbol)) {
        continue;
      }
      for (var j = 0; j < candidates.length; j++) {
        final state = candidates[j];
        if (state.symbol.kind != .class$ ||
            state.path != widget.path ||
            identical(state, widget) ||
            !loc.range.start.within(state.symbol)) {
          continue;
        }
        if (_referencedOnlyWithin(
          refsByCandidate[j],
          widget.symbol,
          widget.path,
        )) {
          out.add((
            filePath: _relPath(state.path, rootPath),
            range: state.symbol.declarationRange,
          ));
        }
        break;
      }
    }
    return out;
  }

  /// Whether every *code* reference in [refs] lies within [enclosing] in
  /// [path] — used to confirm a paired State subclass is reachable only from
  /// its widget. Doc-comment links are ignored: documentation never keeps code
  /// alive, so it must not block coupling.
  bool _referencedOnlyWithin(
    List<Location> refs,
    DocumentSymbol enclosing,
    String path,
  ) => refs.every(
    (loc) =>
        _isDocReference(loc) ||
        (SourceIndex.pathOf(loc.uri) == path &&
            loc.range.start.within(enclosing)),
  );

  /// Whether [candidate] — already classified as unused under
  /// `--unused-union-members` — is kept dead by *type patterns*: at least one
  /// of its non-self, non-doc references is a `case`/switch-expression pattern
  /// match rather than a construction.
  bool _isPatternMatchedClass(Candidate candidate, List<Location> refs) =>
      refs.any(
        (loc) =>
            !_isSelfClassReference(candidate, loc) &&
            !_isDocReference(loc) &&
            _sources.isPatternRef(loc),
      );

  String _relPath(String absPath, String rootPath) =>
      p.split(p.relative(absPath, from: rootPath)).join('/');

  static int _byLocation(UnusedDeclaration a, UnusedDeclaration b) {
    final byFile = a.filePath.compareTo(b.filePath);
    if (byFile != 0) {
      return byFile;
    }
    final byLine = a.line.compareTo(b.line);
    return byLine != 0 ? byLine : a.column.compareTo(b.column);
  }
}

/// The remove-safety pre-pass: facts gathered up front so the reporting loop
/// stays a set of cheap lookups when deciding which findings are report-only
/// (`removalBlocked`) because auto-removing them would break the build.
///
/// * [emptiedEnums] — enums every one of whose values would be removed while
///   the enum type is still referenced, leaving `enum E {}` (a compile error).
/// * [blockedCtorClasses] — live classes all of whose constructors are dead:
///   removing them synthesizes an implicit default constructor that strands
///   `final` fields or breaks super-constructor forwarding.
/// * [enumValuesIterated] — enums whose values are all reachable through
///   `.values` iteration, so a value reached only that way is used, not dead,
///   and is suppressed entirely rather than reported.
class _RemoveSafety {
  const _RemoveSafety({
    required this.emptiedEnums,
    required this.blockedCtorClasses,
    required this.enumValuesIterated,
  });

  factory _RemoveSafety.analyze(
    Ciach finder,
    List<Candidate> candidates,
    List<RefStatus> statuses,
    List<List<Location>> refsByCandidate,
    Map<String, Set<String>> deadClassNames,
  ) {
    final sources = finder._sources;
    final enumTypeHasRef = <DeclKey, bool>{};
    final enumValueTotal = <DeclKey, int>{};
    final enumValueDead = <DeclKey, int>{};
    final enumValuesIterated = <DeclKey>{};
    final ctorTotal = <DeclKey, int>{};
    final ctorDead = <DeclKey, int>{};
    final ctorForwardsSuper = <DeclKey, bool>{};
    final classByKey = <DeclKey, Candidate>{};

    for (var i = 0; i < candidates.length; i++) {
      final candidate = candidates[i];
      final symbol = candidate.symbol;
      final unused = statuses[i] == .unused;
      if (symbol.kind == .enum$ && !candidate.isEnumValue) {
        enumTypeHasRef[candidate.key] = refsByCandidate[i].isNotEmpty;
        if (refsByCandidate[i].any(sources.isDotValuesRef) ||
            sources.enumIteratesOwnValues(candidate)) {
          enumValuesIterated.add(candidate.key);
        }
      } else if (candidate.isEnumValue) {
        if (candidate.containerKey case final key?) {
          enumValueTotal.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (unused) {
            enumValueDead.update(key, (n) => n + 1, ifAbsent: () => 1);
          }
        }
      } else if (symbol.kind == .class$) {
        classByKey[candidate.key] = candidate;
      } else if (symbol.kind == .constructor) {
        if (candidate.containerKey case final key?) {
          ctorTotal.update(key, (n) => n + 1, ifAbsent: () => 1);
          if (unused) {
            ctorDead.update(key, (n) => n + 1, ifAbsent: () => 1);
            if (sources.ctorForwardsSuper(candidate)) {
              ctorForwardsSuper[key] = true;
            }
          }
        }
      }
    }

    final emptiedEnums = <DeclKey>{};
    for (final MapEntry(:key, value: total) in enumValueTotal.entries) {
      final dead = enumValueDead[key] ?? 0;
      if (dead == 0 || dead != total) {
        continue;
      }
      // Conservative: if the enum-type candidate is missing we cannot prove the
      // enum is itself being removed, so assume it stays and block.
      if (enumTypeHasRef[key] ?? true) {
        emptiedEnums.add(key);
      }
    }

    final blockedCtorClasses = <DeclKey>{};
    for (final MapEntry(:key, value: total) in ctorTotal.entries) {
      final dead = ctorDead[key] ?? 0;
      if (dead == 0 || dead != total) {
        continue;
      }
      // A dead class is removed whole (its constructors go with it), so its
      // constructors are never reported on their own — nothing to guard.
      if (deadClassNames[key.path]?.contains(key.name) ?? false) {
        continue;
      }
      final classCandidate = classByKey[key];
      final hasFinalField =
          classCandidate != null &&
          sources.classHasFinalInstanceField(classCandidate);
      if (hasFinalField || (ctorForwardsSuper[key] ?? false)) {
        blockedCtorClasses.add(key);
      }
    }

    return _RemoveSafety(
      emptiedEnums: emptiedEnums,
      blockedCtorClasses: blockedCtorClasses,
      enumValuesIterated: enumValuesIterated,
    );
  }

  final Set<DeclKey> emptiedEnums;
  final Set<DeclKey> blockedCtorClasses;
  final Set<DeclKey> enumValuesIterated;
}
