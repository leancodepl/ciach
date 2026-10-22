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

/// The operators of one override hierarchy, and the candidates among them.
final class OperatorHierarchy {
  OperatorHierarchy(this.members, this.operators);

  /// The names of the members, as in `operator +`.
  final Set<Location> members;
  final List<Candidate> operators;

  /// The name that every member has, such as `+` or `[]=`.
  String get name => operators.first.symbol.name;
}

/// Returns the override hierarchies of [operators] that lie inside
/// [analysisRoot]. Operators of one hierarchy share it.
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
          for (final hierarchy in overlapping) ...hierarchy.operators,
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

  late final _implementations = CachedMap<Location, Future<List<Location>>>(
    (member) => _client.implementations(.parse(member.uri), member.range.start),
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
      final related = await Future.wait([
        _implementations[member],
        _overriddenOf(member, kind),
      ]);
      for (final location in related.flattened) {
        if (!_isInside(location)) {
          return null;
        }
        if (members.add(location)) {
          pending.add(location);
        }
      }
    }
    return members;
  }

  /// Returns the operators of [kind] in the supertypes of the type that
  /// declares [member]. An extension member has none.
  Future<List<Location>> _overriddenOf(
    Location member,
    _OperatorKind kind,
  ) async =>
      await symbolCovering(await _symbols[member.uri], member.range.start)?.let(
        (type) => _overriddenIn(
          .new(uri: member.uri, range: type.selectionRange),
          kind,
        ),
      ) ??
      const [];

  /// Returns the operators of [operator]'s kind in all supertypes of [type].
  /// It visits every supertype, because a type can inherit an operator from
  /// two of them.
  Future<List<Location>> _overriddenIn(
    Location type,
    _OperatorKind operator,
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
        if (await _operatorIn(supertype, operator) case final declared?) {
          overridden.add(declared);
        }
      }
    }
    return overridden;
  }

  /// Returns the operator of [operator]'s kind that [type] declares.
  Future<Location?> _operatorIn(Location type, _OperatorKind operator) async =>
      symbolNamedAt(await _symbols[type.uri], type.range.start)?.children
          ?.firstWhereOrNull(
            (member) =>
                member.isOperator &&
                member.name == operator.name &&
                member.hasNoParameters == operator.isUnary,
          )
          ?.let<Location>(
            (member) => .new(uri: type.uri, range: member.selectionRange),
          );

  bool _isInside(Location declaration) =>
      Uri.parse(declaration.uri).isScheme('file') &&
      analysisRootContains(_analysisRoot, SourceIndex.pathOf(declaration.uri));
}
