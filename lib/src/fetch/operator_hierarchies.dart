/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Collects the override hierarchy of each operator: the operator, every
/// operator that overrides it and every operator that it overrides, also
/// through a second supertype, as in `class C implements A, B`.
library;

import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Range, TypeHierarchyItem;

/// An operator declaration, at its name: `+` in `operator +`.
final class OperatorDeclaration {
  const OperatorDeclaration(this.path, this.name);

  OperatorDeclaration.at(Location location)
    : this(SourceIndex.pathOf(location.uri), location.range);

  /// The absolute path of the declaring file.
  final String path;

  final Range name;

  @override
  bool operator ==(Object other) =>
      other is OperatorDeclaration && other.path == path && other.name == name;

  @override
  int get hashCode => Object.hash(path, name);
}

/// The operators of an override hierarchy, and the candidates among them.
final class OperatorHierarchy {
  OperatorHierarchy(this.members, this.operators);

  final Set<OperatorDeclaration> members;
  final List<Candidate> operators;
}

/// The override hierarchies of [operators] whose members are all inside
/// [analysisRoot]. Two operators in one hierarchy share it.
Future<List<OperatorHierarchy>> operatorHierarchies(
  LspClient client,
  List<Candidate> operators, {
  required String analysisRoot,
  required int concurrency,
}) async {
  final lookup = _HierarchyLookup(client, analysisRoot);
  final membersOf = await mapPooled(operators, concurrency, lookup.membersOf);
  final hierarchies = <OperatorHierarchy>[];
  for (final (i, members) in membersOf.indexed) {
    if (members == null) {
      continue;
    }
    // Both lookups found the whole hierarchy, so their members are the same.
    if (hierarchies.firstWhereOrNull(
          (hierarchy) => hierarchy.members.containsAll(members),
        )
        case final hierarchy?) {
      hierarchy.operators.add(operators[i]);
    } else {
      hierarchies.add(.new(members, [operators[i]]));
    }
  }
  return hierarchies;
}

/// The requests that find the members of a hierarchy, with the answers that
/// the hierarchies of several operators share.
final class _HierarchyLookup {
  _HierarchyLookup(this._client, this._analysisRoot);

  final LspClient _client;
  final String _analysisRoot;

  late final _symbols = CachedMap<String, Future<List<DocumentSymbol>>>(
    (uri) => _client.documentSymbol(.parse(uri)),
  );

  /// The direct supertypes of each type, by the type's name.
  final _supertypes =
      <({String uri, Range name}), Future<List<TypeHierarchyItem>>>{};

  /// [operator] and every member of its hierarchy, or `null` when one of them
  /// is outside the analysis root, such as `Object.==`.
  Future<Set<OperatorDeclaration>?> membersOf(Candidate operator) async {
    final start = OperatorDeclaration(
      operator.path,
      operator.symbol.selectionRange,
    );
    final members = {start};
    final pending = [start];
    while (pending.isNotEmpty) {
      final member = pending.removeLast();
      final uri = File(member.path).uri;
      final related = [
        ...await _client.implementations(uri, member.name.start),
        ...await _overridden(member, operator.symbol),
      ];
      for (final location in related) {
        if (!_isInside(location.uri)) {
          return null;
        }
        final found = OperatorDeclaration.at(location);
        if (members.add(found)) {
          pending.add(found);
        }
      }
    }
    return members;
  }

  /// The operators like [operator] in the supertypes of the type that
  /// declares [member], transitively. The server's `super` request names only
  /// one of them when the type has two supertypes that declare the operator.
  Future<List<Location>> _overridden(
    OperatorDeclaration member,
    DocumentSymbol operator,
  ) async {
    final declaringType = await _client.declaringType(
      File(member.path).uri,
      member.name.start,
    );
    if (declaringType == null) {
      return const [];
    }
    final overridden = <Location>[];
    final seen = <({String uri, Range name})>{};
    final pending = [declaringType];
    while (pending.isNotEmpty) {
      final type = pending.removeLast();
      final supertypes = _supertypes[_nameOf(type)] ??= _client.supertypes(
        type,
      );
      for (final supertype in await supertypes) {
        if (!seen.add(_nameOf(supertype))) {
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

  /// [type]'s own operator with the name of [operator], and unary when
  /// [operator] is: a class can declare both `-()` and `-(other)`.
  Future<Location?> _operatorIn(
    TypeHierarchyItem type,
    DocumentSymbol operator,
  ) async {
    final declaration = (await _symbols[type.uri]).firstWhereOrNull(
      (symbol) => symbol.selectionRange == type.selectionRange,
    );
    return declaration?.children
        ?.firstWhereOrNull(
          (member) =>
              member.isOperator &&
              member.name == operator.name &&
              member.hasNoParameters == operator.hasNoParameters,
        )
        ?.let<Location>(
          (member) => .new(uri: type.uri, range: member.selectionRange),
        );
  }

  ({String uri, Range name}) _nameOf(TypeHierarchyItem type) =>
      (uri: type.uri, name: type.selectionRange);

  /// Whether [uri] names a file inside the analysis root.
  bool _isInside(String uri) {
    final parsed = Uri.parse(uri);
    return parsed.isScheme('file') &&
        p.isWithin(_analysisRoot, parsed.toFilePath());
  }
}
