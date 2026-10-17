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
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/paths.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Range, TypeHierarchyItem;

/// A declaration, by its file and the range of its name: `+` in
/// `operator +`, or `Vector` in `class Vector`.
final class DeclarationName {
  const DeclarationName(this.uri, this.range);

  DeclarationName.of(Location location)
    : this(.parse(location.uri), location.range);

  DeclarationName.ofType(TypeHierarchyItem type)
    : this(.parse(type.uri), type.selectionRange);

  /// The file. The SDK's files can have `dart:` URIs.
  final Uri uri;

  final Range range;

  /// The absolute path of the file, which has a `file:` URI.
  String get path => uri.toFilePath();

  @override
  bool operator ==(Object other) =>
      other is DeclarationName && other.uri == uri && other.range == range;

  @override
  int get hashCode => Object.hash(uri, range);
}

/// The operators of an override hierarchy, and the candidates among them.
final class OperatorHierarchy {
  OperatorHierarchy(this.members, this.operators);

  final Set<DeclarationName> members;
  final List<Candidate> operators;

  /// The name of every member: `+`, `[]=` or `>=`.
  String get name => operators.first.symbol.name;
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

/// An operator's name and whether it is unary: a class can declare both
/// `-()` and `-(other)`.
typedef _OperatorKind = ({String name, bool isUnary});

/// The requests that find the members of a hierarchy, with the answers that
/// the hierarchies of several operators share.
final class _HierarchyLookup {
  _HierarchyLookup(this._client, this._analysisRoot);

  final LspClient _client;
  final String _analysisRoot;

  late final _symbols = CachedMap<Uri, Future<List<DocumentSymbol>>>(
    _client.documentSymbol,
  );

  late final _implementations =
      CachedMap<DeclarationName, Future<List<Location>>>(
        (member) => _client.implementations(member.uri, member.range.start),
      );

  /// The type hierarchy item of each type.
  late final _types = CachedMap<DeclarationName, Future<TypeHierarchyItem?>>(
    (type) => _client.declaringType(type.uri, type.range.start),
  );

  /// The direct supertypes of each type.
  late final _supertypes =
      CachedMap<DeclarationName, Future<List<TypeHierarchyItem>>>(
        (type) async =>
            await (await _types[type])?.let(_client.supertypes) ?? const [],
      );

  /// The operators of a kind in the supertypes of a type. The operators of
  /// one type share these lookups.
  late final _overridden =
      CachedMap<
        ({DeclarationName type, _OperatorKind operator}),
        Future<List<Location>>
      >((lookup) => _overriddenIn(lookup.type, lookup.operator));

  /// [operator] and every member of its hierarchy, or `null` when one of them
  /// is outside the analysis root, such as `Object.==`.
  Future<Set<DeclarationName>?> membersOf(Candidate operator) async {
    final kind = (
      name: operator.symbol.name,
      isUnary: operator.symbol.hasNoParameters,
    );
    final start = DeclarationName(
      File(operator.path).uri,
      operator.symbol.selectionRange,
    );
    final members = {start};
    // The server lists the overrides of an override among those of the member
    // that it overrides, so only a member reached through a supertype needs
    // its own lookup.
    final pending = [(member: start, listsOverrides: true)];
    while (pending.isNotEmpty) {
      final (:member, :listsOverrides) = pending.removeLast();
      // Both lookups start before either is awaited.
      final overridesLookup = listsOverrides
          ? _implementations[member]
          : Future.value(const <Location>[]);
      final overriddenLookup = _overriddenOf(member, kind);
      final overrides = await overridesLookup;
      for (final location in [...overrides, ...await overriddenLookup]) {
        final found = DeclarationName.of(location);
        if (!_isInside(found)) {
          return null;
        }
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

  /// The operators of [kind] in the supertypes of the type that declares
  /// [member]. A member of an extension has none.
  Future<List<Location>> _overriddenOf(
    DeclarationName member,
    _OperatorKind kind,
  ) async =>
      switch (symbolCovering(await _symbols[member.uri], member.range.start)) {
        final type? when type.kind != .namespace =>
          await _overridden[(
            type: .new(member.uri, type.selectionRange),
            operator: kind,
          )],
        _ => const [],
      };

  /// The operators of [operator]'s kind in the supertypes of [type],
  /// transitively. The server's `super` request names only one of them when
  /// the type has two supertypes that declare the operator.
  Future<List<Location>> _overriddenIn(
    DeclarationName type,
    _OperatorKind operator,
  ) async {
    final overridden = <Location>[];
    final seen = <DeclarationName>{};
    final pending = [type];
    while (pending.isNotEmpty) {
      for (final item in await _supertypes[pending.removeLast()]) {
        final supertype = DeclarationName.ofType(item);
        if (!seen.add(supertype)) {
          continue;
        }
        _types[supertype] = .value(item);
        pending.add(supertype);
        if (await _operatorIn(supertype, operator) case final declared?) {
          overridden.add(declared);
        }
      }
    }
    return overridden;
  }

  /// The operator of [operator]'s kind that [type] declares.
  Future<Location?> _operatorIn(
    DeclarationName type,
    _OperatorKind operator,
  ) async => symbolNamedAt(await _symbols[type.uri], type.range.start)?.children
      ?.firstWhereOrNull(
        (member) =>
            member.isOperator &&
            member.name == operator.name &&
            member.hasNoParameters == operator.isUnary,
      )
      ?.let<Location>(
        (member) =>
            .new(uri: type.uri.toString(), range: member.selectionRange),
      );

  bool _isInside(DeclarationName declaration) =>
      declaration.uri.isScheme('file') &&
      analysisRootContains(_analysisRoot, declaration.path);
}
