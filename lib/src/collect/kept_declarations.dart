/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:collection/collection.dart';

final _log = Logger('ciach.finder');

/// The declarations a run leaves unchecked on purpose: entry points a
/// framework or a tool calls, members called from outside the Dart source,
/// and what a `// ciach:` marker keeps. Each is recorded with its reason, for
/// `--verbose`, together with the type that has to stay with it.
final class KeptDeclarations {
  KeptDeclarations(this._entryPoints);

  final EntryPoints _entryPoints;

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
    final sorted = _skippedEntryPoints.sorted(
      (a, b) => switch (a.path.compareTo(b.path)) {
        0 => a.line.compareTo(b.line),
        final byFile => byFile,
      },
    );
    for (final skipped in sorted.whereNot((it) => it.name == 'main')) {
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
      final reason =
          candidate.container == null &&
              candidate.outline.element.declaresMembers
          ? _entryPointContainers[DeclKey(relativePath, candidate.name)]
          : null;
      if (reason == null) {
        yield candidate;
        continue;
      }
      _skip(relativePath, candidate, candidate.name, reason);
    }
  }

  /// Returns whether [candidate], which the rules read as [declaration], is
  /// called by a framework or a tool. Such a declaration has no reference in
  /// the source code. [containerMembers] are the members that the rules keep
  /// in the type that declares it. Every entry point that is found here is
  /// recorded, so that `--verbose` can list it.
  bool isEntryPoint(
    Candidate candidate,
    ResolvedDeclaration declaration,
    List<KeptMembers> containerMembers,
  ) {
    final ResolvedDeclaration(:relativePath, :outline, :container) =
        declaration;
    final qualified = declaration.qualifiedName;
    final rule = _entryPoints.match(declaration);
    if (rule != null && container != null) {
      _entryPointContainers[DeclKey(relativePath, container)] ??=
          'declares the entry point $qualified';
    }
    final reason =
        rule?.reasonFor(declaration) ??
        containerMembers
            .firstWhereOrNull((members) => members.selection.includes(outline))
            ?.reason;
    if (reason == null) {
      return false;
    }
    _skip(relativePath, candidate, qualified, reason);
    return true;
  }

  /// Records [candidate] as kept by the marker [kept], and its type too.
  void byMarker(String relativePath, Candidate candidate, MarkerAt kept) {
    final container = candidate.container;
    final qualified = candidate.outline.element.qualifiedName(container);
    if (container != null) {
      _entryPointContainers[DeclKey(relativePath, container)] ??=
          'declares $qualified, kept by `// ${kept.marker}`';
    }
    _skip(
      relativePath,
      candidate,
      qualified,
      'kept by `// ${kept.marker}` on line ${kept.line + 1}',
    );
  }

  /// Records [candidate], named [name] in the log, as skipped for [reason].
  void _skip(String path, Candidate candidate, String name, String reason) =>
      _skippedEntryPoints.add((
        path: path,
        line: candidate.namePosition.line + 1,
        name: name,
        reason: reason,
      ));
}

/// A skipped entry point: root-relative POSIX path, one-based line, the name
/// as the rule spells it, and why.
typedef _SkippedEntryPoint = ({
  String path,
  int line,
  String name,
  String reason,
});
