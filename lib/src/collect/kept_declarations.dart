/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/resolved_classes.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/log.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.finder');

/// The declarations a run leaves unchecked on purpose: entry points a
/// framework or a tool calls, members called from outside the Dart source,
/// and what a `// ciach:` marker keeps. Each is recorded with its reason, for
/// `--verbose`, together with the type that has to stay with it.
final class KeptDeclarations {
  KeptDeclarations(List<EntryPoint> rules, ResolvedClasses resolvedClasses)
    : _entryPoints = EntryPoints(rules),
      _resolvedClasses = resolvedClasses;

  final EntryPoints _entryPoints;
  final ResolvedClasses _resolvedClasses;

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
  /// declaration has no reference in the source code. [containerRules] are
  /// the rules that keep some members of the type that declares [candidate].
  /// Every entry point that is found here is recorded, so that `--verbose`
  /// can list it.
  bool isEntryPoint(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
    List<EntryPoint> containerRules,
  ) {
    final symbol = candidate.symbol;
    final container = candidate.container;
    final name = symbol.declarationName(container);
    final qualified = container?.let((container) => '$container.$name') ?? name;
    final declaration = _declarationOf(
      relativePath,
      candidate,
      leadingMetadata,
    );
    final rule = _entryPoints.match(declaration);
    if (rule != null && container != null) {
      _entryPointContainers[DeclKey(relativePath, container)] ??= rule
          .containerReason(qualified);
    }
    final reason =
        rule?.reasonFor(declaration) ??
        containerRules
            .firstWhereOrNull((rule) => rule.members!.includes(symbol))
            ?.memberReason;
    if (reason == null) {
      return false;
    }
    _skippedEntryPoints.add((
      path: relativePath,
      line: symbol.selectionRange.start.line + 1,
      name: qualified,
      reason: reason,
    ));
    return true;
  }

  /// Returns the rules that keep some members of [candidate], a type, or
  /// `null` when [candidate] is not a type.
  List<EntryPoint>? rulesForMembersOf(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
  ) => typeLikeKinds.contains(candidate.symbol.kind)
      ? _entryPoints.keepingMembersOf(
          _declarationOf(relativePath, candidate, leadingMetadata),
        )
      : null;

  ResolvedDeclaration _declarationOf(
    String relativePath,
    Candidate candidate,
    Iterable<SemanticToken> leadingMetadata,
  ) => .new(
    relativePath: relativePath,
    symbol: candidate.symbol,
    container: candidate.container,
    inEnum: candidate.containerSymbol?.kind == .enum$,
    leadingMetadata: leadingMetadata,
    annotations: _resolvedClasses.annotationsOf(
      candidate.path,
      leadingMetadata,
    ),
    supertypes: _resolvedClasses.supertypesOf(candidate.path, candidate.symbol),
  );

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
}

/// A skipped entry point: root-relative POSIX path, one-based line, the name
/// as the rule spells it, and why.
typedef _SkippedEntryPoint = ({
  String path,
  int line,
  String name,
  String reason,
});
