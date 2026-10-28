/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/annotation_types.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/js_interop.dart';
import 'package:ciach/src/conventions/test_reflective_loader.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

final _log = Logger('ciach.finder');

/// The declarations a run leaves unchecked on purpose: entry points a
/// framework or a tool calls, members called from outside the Dart source,
/// and what a `// ciach:` marker keeps. Each is recorded with its reason, for
/// `--verbose`, together with the type that has to stay with it.
final class KeptDeclarations {
  KeptDeclarations(
    List<EntryPoint> rules,
    SourceIndex sources,
    AnnotationTypes annotationTypes,
  ) : _entryPoints = EntryPoints(rules),
      _sources = sources,
      _annotationTypes = annotationTypes;

  final EntryPoints _entryPoints;
  final SourceIndex _sources;
  final AnnotationTypes _annotationTypes;

  /// Skipped as entry points this run, for `--verbose`.
  final _skippedEntryPoints = <_SkippedEntryPoint>[];

  /// Why each type whose member is an entry point or kept by a marker is not
  /// a candidate, by `(relative path, type name)`: the generated call that
  /// reaches `MyPlugin.registerWith` names `MyPlugin` too, and removing the
  /// type would take the kept member with it.
  final _entryPointContainers = <DeclKey, String>{};

  /// One line per skipped entry point, except the ubiquitous `main`.
  void report() {
    if (!_log.isLoggable(.FINE)) {
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
      _log.fine(
        'Skipped ${skipped.path}:${skipped.line} ${skipped.name}: ${skipped.reason}.',
      );
    }
  }

  /// [candidates] less the types a member entry point lives in; see
  /// [_entryPointContainers]. Their other members stay candidates.
  Iterable<Candidate> withoutContainers(
    List<Candidate> candidates,
    String relativePath,
  ) sync* {
    for (final candidate in candidates) {
      final symbol = candidate.symbol;
      final reason =
          candidate.container == null && typeLikeKinds.contains(symbol.kind)
          ? _entryPointContainers[DeclKey(relativePath, symbol.name)]
          : null;
      if (reason == null) {
        yield candidate;
        continue;
      }
      _skippedEntryPoints.add((
        path: relativePath,
        line: symbol.selectionRange.start.line + 1,
        name: symbol.name,
        reason: reason,
      ));
    }
  }

  /// Returns whether [candidate] is called by a framework or a tool. Such a
  /// declaration has no reference in the source code. Every entry point that
  /// is found here is recorded, so that `--verbose` can list it.
  bool isEntryPoint(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
    ExportedMembers? containerExports,
  ) {
    final symbol = candidate.symbol;
    final container = candidate.container;
    final rule = _entryPoints.match(
      relativePath,
      symbol,
      container,
      containerSuperclass: () => candidate.containerSymbol?.let(
        (containerSymbol) => _superclassOf(candidate.path, containerSymbol),
      ),
      annotationTypes: _annotationTypes.of(candidate.path, leadingMetadata),
      inEnum: candidate.containerSymbol?.kind == .enum$,
    );
    if (rule != null && container != null) {
      _entryPointContainers[DeclKey(relativePath, container)] ??= switch ((
        rule.superclass,
        rule.annotation,
      )) {
        (final superclass?, _) =>
          'extends `$superclass`, so its public methods are entry points',
        (_, _?) =>
          'declares the entry point $container.${symbol.declarationName(container)}',
        _ => 'declares the entry point ${rule.name}',
      };
    }
    final reason =
        rule?.let(
          (rule) => rule.name == container
              ? 'the unnamed constructor of the entry point ${rule.name}'
              : rule.reason,
        ) ??
        _calledFromOutside(candidate, leadingMetadata, containerExports);
    if (reason == null) {
      return false;
    }
    final name = symbol.declarationName(container);
    _skippedEntryPoints.add((
      path: relativePath,
      line: symbol.selectionRange.start.line + 1,
      name: container?.let((container) => '$container.$name') ?? name,
      reason: reason,
    ));
    return true;
  }

  /// Records [candidate] as kept by the marker [kept], and its type too.
  void byMarker(String relativePath, Candidate candidate, MarkerAt kept) {
    final symbol = candidate.symbol;
    final container = candidate.container;
    final name = symbol.declarationName(container);
    final qualified = container?.let((container) => '$container.$name') ?? name;
    if (container != null) {
      _entryPointContainers[DeclKey(relativePath, container)] ??=
          'declares $qualified, kept by `// ${kept.marker}`';
    }
    _skippedEntryPoints.add((
      path: relativePath,
      line: symbol.selectionRange.start.line + 1,
      name: qualified,
      reason: 'kept by `// ${kept.marker}` on line ${kept.line + 1}',
    ));
  }

  String? _calledFromOutside(
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
    ExportedMembers? containerExports,
  ) {
    final symbol = candidate.symbol;
    if (isJsExported(leadingMetadata)) {
      return 'exported to JavaScript by `@JSExport`';
    }
    if (isPrivateName(symbol.name) || symbol.kind == .constructor) {
      return null;
    }
    return switch (containerExports) {
      .jsExport => 'exported to JavaScript by `@JSExport` on its class',
      .reflectiveTest
          when symbol.kind == .method && isReflectiveTestMethod(symbol.name) =>
        'run by `defineReflectiveTests`',
      _ => null,
    };
  }

  /// Returns the name of the class that [symbol] extends. [symbol] is a class
  /// that is declared in the file at [path]. Returns `null` when [symbol] is
  /// not a class, or when the class has no `extends` clause.
  String? _superclassOf(String path, DocumentSymbol symbol) {
    if (symbol.kind != .class$) {
      return null;
    }
    final start = _sources.offsetOf(path, symbol.selectionRange.end);
    final end = _sources.offsetOf(path, symbol.range.end);
    if (start == null || end == null) {
      return null;
    }
    final rest = _sources.content(path).substring(start, end);
    final brace = rest.indexOf('{');
    return _extendsClause
        .firstMatch(brace < 0 ? rest : rest.substring(0, brace))
        ?.namedGroup('superclass');
  }

  /// Matches the `extends` clause that follows a class name. The type
  /// parameters before the clause must not be nested, so a class with
  /// `<T extends List<int>>` is not matched.
  static final _extendsClause = RegExp(
    r'^\s*(?:<[^<>]*>)?\s*extends\s+(?<superclass>[A-Za-z_$][\w$]*)',
  );
}

/// The members of a type that are called from outside the Dart source.
enum ExportedMembers { jsExport, reflectiveTest }

/// A skipped entry point: root-relative POSIX path, one-based line, the name
/// as the rule spells it, and why.
typedef _SkippedEntryPoint = ({
  String path,
  int line,
  String name,
  String reason,
});

/// Returns which members of the type [symbol] are called from outside the
/// Dart source. The annotation on the type decides this. Returns `null`
/// when [symbol] is not a type, or when the type has no such annotation.
ExportedMembers? exportsOf(
  DocumentSymbol symbol,
  Iterable<SemanticToken> leadingMetadata,
) {
  if (!typeLikeKinds.contains(symbol.kind)) {
    return null;
  }
  if (isJsExported(leadingMetadata)) {
    return .jsExport;
  }
  if (isReflectiveTest(leadingMetadata)) {
    return .reflectiveTest;
  }
  return null;
}
