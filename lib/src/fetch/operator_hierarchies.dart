/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Collects the override hierarchy of each operator: the operator, the
/// operators that it overrides and the operators that override it.
library;

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, TypeHierarchyItem;

/// One override hierarchy: operators that override each other.
final class OperatorHierarchy {
  OperatorHierarchy(this.members, this.candidates);

  /// The location of each member's name, such as `+` in `operator +`.
  final Set<Location> members;

  /// The members that ciach checks.
  final List<Candidate> candidates;

  /// The name of every member, such as `+` or `[]=`.
  String get name => candidates.first.symbol.name;
}

/// Returns the override hierarchies of [operators] that lie inside
/// [analysisRoot]. Two operators that override each other share one.
///
/// `==` is always left out, because every `==` overrides `Object.==`.
Future<List<OperatorHierarchy>> operatorHierarchies(
  LspClient client,
  List<Candidate> operators, {
  required String analysisRoot,
  required int concurrency,
}) async {
  final lookup = _HierarchyLookup(client, analysisRoot);
  // Skipping `==` here saves the requests that would only reach `Object.==`.
  final lookedUp = operators.where((o) => o.symbol.name != '==').toList();
  final membersOf = await mapPooled(lookedUp, concurrency, lookup.membersOf);
  var hierarchies = <OperatorHierarchy>[];
  for (final (i, members) in membersOf.indexed) {
    if (members == null) {
      continue;
    }
    // The lookups of two operators in one hierarchy can return different
    // members, so hierarchies that share a member are merged.
    final overlapping = hierarchies
        .where((hierarchy) => hierarchy.members.any(members.contains))
        .toList();
    hierarchies = [
      ...hierarchies.whereNot(overlapping.contains),
      .new(
        {...members, for (final hierarchy in overlapping) ...hierarchy.members},
        [
          for (final hierarchy in overlapping) ...hierarchy.candidates,
          lookedUp[i],
        ],
      ),
    ];
  }
  return hierarchies;
}

/// An operator's name and whether it is unary, because a class can declare
/// both `-()` and `-(other)`.
final class _OperatorKind {
  const _OperatorKind(this.name, {required this.isUnary});

  final String name;
  final bool isUnary;
}

/// Finds the members of hierarchies, and caches the server's answers, which
/// several hierarchies need.
final class _HierarchyLookup {
  _HierarchyLookup(this._client, this._analysisRoot);

  final LspClient _client;
  final String _analysisRoot;

  late final _symbols = CachedMap<String, Future<List<DocumentSymbol>>>(
    (uri) => _client.documentSymbol(.parse(uri)),
  );

  /// The subtypes of each type, the direct and the indirect ones.
  late final _subtypes = CachedMap<Location, Future<List<Location>>>(
    (type) => _client.implementations(.parse(type.uri), type.range.start),
  );

  /// The direct supertypes of each type.
  late final _supertypes = CachedMap<Location, Future<List<TypeHierarchyItem>>>(
    (type) async =>
        await (await _client.declaringType(
          .parse(type.uri),
          type.range.start,
        ))?.let(_client.supertypes) ??
        const [],
  );

  /// Returns [operator] and the other members of its hierarchy, or `null`
  /// when one of them is outside the analysis root, such as `Object.==`.
  Future<Set<Location>?> membersOf(Candidate operator) async {
    final kind = _OperatorKind(
      operator.symbol.name,
      isUnary: operator.symbol.hasNoParameters,
    );
    final start = Location(
      uri: operator.uri.toString(),
      range: operator.symbol.selectionRange,
    );
    final members = {start};
    final pending = [start];
    while (pending.isNotEmpty) {
      final member = pending.removeLast();
      for (final location in await _relatedTo(member, kind)) {
        if (!_isInsideAnalysisRoot(location)) {
          return null;
        }
        if (members.add(location)) {
          pending.add(location);
        }
      }
    }
    return members;
  }

  /// Returns the operators that [member] overrides and that override it,
  /// and those that a subtype of its type inherits along with it, as `Both`
  /// inherits both `+` in `abstract class Both implements Left, Right {}`.
  /// A member of an extension has none.
  Future<List<Location>> _relatedTo(Location member, _OperatorKind kind) async {
    final declaring = symbolCovering(
      await _symbols[member.uri],
      member.range.start,
    );
    if (declaring == null) {
      return const [];
    }
    final type = Location(uri: member.uri, range: declaring.selectionRange);
    return [
      ...await _operatorsInSupertypes(type, kind),
      for (final subtype in await _subtypes[type]) ...[
        ?await _declaredOperator(subtype, kind),
        ...await _operatorsInSupertypes(subtype, kind),
      ],
    ];
  }

  /// Returns the operators of [kind] that the supertypes of [type] declare,
  /// the direct and the indirect ones.
  Future<List<Location>> _operatorsInSupertypes(
    Location type,
    _OperatorKind kind,
  ) async {
    final overridden = <Location>[];
    final seen = <Location>{};
    final pending = [type];
    while (pending.isNotEmpty) {
      for (final item in await _supertypes[pending.removeLast()]) {
        final supertype = Location(uri: item.uri, range: item.selectionRange);
        if (!seen.add(supertype)) {
          continue;
        }
        pending.add(supertype);
        if (await _declaredOperator(supertype, kind) case final declared?) {
          overridden.add(declared);
        }
      }
    }
    return overridden;
  }

  /// Returns the operator of [kind] that [type] declares, if any.
  Future<Location?> _declaredOperator(
    Location type,
    _OperatorKind kind,
  ) async => symbolNamedAt(await _symbols[type.uri], type.range.start)?.children
      ?.firstWhereOrNull(
        (member) =>
            member.isOperator &&
            member.name == kind.name &&
            member.hasNoParameters == kind.isUnary,
      )
      ?.let<Location>(
        (member) => .new(uri: type.uri, range: member.selectionRange),
      );

  bool _isInsideAnalysisRoot(Location declaration) =>
      Uri.parse(declaration.uri).isScheme('file') &&
      analysisRootContains(_analysisRoot, SourceIndex.pathOf(declaration.uri));
}
