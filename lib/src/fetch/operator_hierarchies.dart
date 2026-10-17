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

  /// The name of every member: `+`, `[]=` or `>=`.
  String get name => operators.first.symbol.name;

  /// Whether the candidates are members of classes, mixins or enums and
  /// return `bool`, as comparisons do. The members that they override return
  /// a supertype of `bool`, and those that override them return `bool`.
  bool get returnsBool => operators.every(
    (operator) =>
        !operator.isExtensionMember &&
        operator.outline.element.returnType == 'bool',
  );
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

  late final _implementations =
      CachedMap<OperatorDeclaration, Future<List<Location>>>(
        (member) =>
            _client.implementations(File(member.path).uri, member.name.start),
      );

  /// The type hierarchy item of each type, by its name.
  late final _types = CachedMap<_TypeName, Future<TypeHierarchyItem?>>(
    (type) => _client.declaringType(.parse(type.uri), type.name.start),
  );

  /// The direct supertypes of each type, by its name.
  late final _supertypes =
      CachedMap<_TypeName, Future<List<TypeHierarchyItem>>>(
        (type) async =>
            await (await _types[type])?.let(_client.supertypes) ?? const [],
      );

  /// The operators like an operator of a type in the supertypes of that type,
  /// by the type and the operator. The operators of one type share these
  /// lookups.
  late final _overridden =
      CachedMap<
        ({_TypeName type, String name, bool isUnary}),
        Future<List<Location>>
      >(_overriddenIn);

  /// [operator] and every member of its hierarchy, or `null` when one of them
  /// is outside the analysis root, such as `Object.==`.
  Future<Set<OperatorDeclaration>?> membersOf(Candidate operator) async {
    final start = OperatorDeclaration(
      operator.path,
      operator.symbol.selectionRange,
    );
    final members = {start};
    // The server lists the overrides of an override among those of the member
    // that it overrides, so only a member reached through a supertype needs
    // its own lookup.
    final pending = [(member: start, listsOverrides: true)];
    while (pending.isNotEmpty) {
      final (:member, :listsOverrides) = pending.removeLast();
      final overrides = listsOverrides
          ? await _implementations[member]
          : const <Location>[];
      final overridden =
          await (await _declaringType(member))?.let(
            (type) =>
                _overridden[(
                  type: type,
                  name: operator.symbol.name,
                  isUnary: operator.symbol.hasNoParameters,
                )],
          ) ??
          const <Location>[];
      for (final location in [...overrides, ...overridden]) {
        if (!_isInside(location.uri)) {
          return null;
        }
        final found = OperatorDeclaration.at(location);
        if (members.add(found)) {
          pending.add((
            member: found,
            listsOverrides: !overrides.contains(location),
          ));
        }
      }
    }
    return members;
  }

  /// The name of the type that declares [member], or `null` for a member of
  /// an extension, which has no supertypes.
  Future<_TypeName?> _declaringType(OperatorDeclaration member) async {
    final uri = File(member.path).uri.toString();
    final symbols = await _symbols[uri];
    return symbols
        .firstWhereOrNull(
          (symbol) =>
              symbol.kind != .namespace &&
              symbol.range.contains(member.name.start),
        )
        ?.let<_TypeName>((type) => (uri: uri, name: type.selectionRange));
  }

  /// The operators in the supertypes of the type of [lookup], transitively,
  /// that have the name of its operator and are unary when that operator is:
  /// a class can declare both `-()` and `-(other)`. The server's `super`
  /// request names only one of them when the type has two supertypes that
  /// declare the operator.
  Future<List<Location>> _overriddenIn(
    ({_TypeName type, String name, bool isUnary}) lookup,
  ) async {
    final overridden = <Location>[];
    final seen = <_TypeName>{};
    final pending = [lookup.type];
    while (pending.isNotEmpty) {
      for (final supertype in await _supertypes[pending.removeLast()]) {
        final name = (uri: supertype.uri, name: supertype.selectionRange);
        if (!seen.add(name)) {
          continue;
        }
        _types[name] = .value(supertype);
        pending.add(name);
        if (await _operatorIn(name, lookup.name, isUnary: lookup.isUnary)
            case final declared?) {
          overridden.add(declared);
        }
      }
    }
    return overridden;
  }

  /// The operator named [name] that [type] declares, unary when [isUnary] is.
  Future<Location?> _operatorIn(
    _TypeName type,
    String name, {
    required bool isUnary,
  }) async => (await _symbols[type.uri])
      .firstWhereOrNull((symbol) => symbol.selectionRange == type.name)
      ?.children
      ?.firstWhereOrNull(
        (member) =>
            member.isOperator &&
            member.name == name &&
            member.hasNoParameters == isUnary,
      )
      ?.let<Location>(
        (member) => .new(uri: type.uri, range: member.selectionRange),
      );

  /// Whether [uri] names a file inside the analysis root.
  bool _isInside(String uri) {
    final parsed = Uri.parse(uri);
    return parsed.isScheme('file') &&
        p.isWithin(_analysisRoot, parsed.toFilePath());
  }
}

/// A class, mixin, enum or extension type, by the file and the range of its
/// name.
typedef _TypeName = ({String uri, Range name});
