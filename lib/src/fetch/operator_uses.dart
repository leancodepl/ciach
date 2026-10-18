/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Finds the uses of operators: `a + b`, `-a`, `a[i]`, `a[i] = v`, `a += b`
/// and the relational patterns `case < 0` and `case >= 10`.
///
/// The reference search misses them. It finds a use of an operator only in
/// the library that declares it, it finds no relational pattern at all, and
/// for an override such as `==`, it lists the uses of every member that the
/// operator overrides, also those in the SDK. But the server reports a compile
/// error at each use once the operator is gone. So the operator and every
/// member of its override hierarchy are renamed in unsaved copies of their
/// files, and every new error is a use.
library;

import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/operator_hierarchies.dart';
import 'package:ciach/src/fetch/unsaved_changes.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Range;

final _log = Logger('ciach.operator_uses');

const _lookupFailed = 'Could not look up the uses of operators; kept them all.';

/// The name that replaces the `operator` keyword. It has the length of the
/// keyword, and spaces replace the operator's name, so that every position
/// stays the same. Every member of a hierarchy gets this name, so each still
/// overrides the others.
const _newName = r'o$$$$$$$';

/// The rounds that rename the operators of a scan, planned while the server
/// has the files on disk, so that the lookups ask about the positions in
/// them.
final class OperatorLookup {
  OperatorLookup._(this._sources, this._operators, this._rounds);

  /// Plans the rounds for [operators], or returns `null` when a request to
  /// the server failed, so that the uses are unknown.
  ///
  /// An operator is left out when its hierarchy has a member outside
  /// [analysisRoot], such as `Object.==`, because the uses of that member
  /// can't be found and the SDK calls `==` without any code that names it.
  /// It is left out too when the server sends no `operator` keyword before
  /// the name of a member.
  static Future<OperatorLookup?> plan({
    required LspClient client,
    required SourceIndex sources,
    required List<Candidate> operators,
    required String analysisRoot,
    required int concurrency,
  }) async {
    if (operators.isEmpty) {
      return ._(sources, operators, const []);
    }
    try {
      final hierarchies = await operatorHierarchies(
        client,
        operators,
        analysisRoot: analysisRoot,
        concurrency: concurrency,
      );
      final renamables = [
        for (final hierarchy in hierarchies)
          if (await _renamesOf(client, sources, hierarchy.members)
              case final renames?)
            _Renamable(hierarchy, renames),
      ];
      return ._(sources, operators, _roundsOf(client, renamables));
    } on LspRequestException catch (e) {
      recordProblem(_lookupFailed, e, path: operators.first.path);
      return null;
    }
  }

  final SourceIndex _sources;
  final List<Candidate> _operators;
  final List<List<_Renamable>> _rounds;

  /// The uses of each operator that ciach can check, by candidate, or `null`
  /// when a request to the server failed. A use of any member of an
  /// operator's override hierarchy counts for each member, as the reference
  /// search counts a call of a method through a subclass. The files stay
  /// changed in [changes] until the caller restores them.
  Future<Map<Candidate, List<Location>>?> usesIn(UnsavedChanges changes) async {
    if (_rounds.isEmpty) {
      return const {};
    }
    _log.info(
      'Looking up the uses of ${plural(_operators.length, 'operator', 'operators')}…',
    );
    try {
      final usesOf = <Candidate, List<Location>>{};
      for (final (i, round) in _rounds.indexed) {
        _log.fine(
          '[${i + 1}/${_rounds.length}] ${round.map((r) => '`${r.hierarchy.name}`').join(', ')}',
        );
        changes.show({
          for (final MapEntry(key: path, value: inFile)
              in round
                  .expand((renamable) => renamable.renames)
                  .groupListsBy((rename) => rename.path)
                  .entries)
            path: _sources.contentWith(path, inFile.expand((r) => r.texts)),
        });
        final errors = await changes.newErrors();
        for (final _Renamable(:hierarchy) in round) {
          final uses = _usesOf(hierarchy, round, errors, _sources);
          for (final operator in hierarchy.operators) {
            usesOf[operator] = uses;
          }
        }
      }
      return usesOf;
    } on LspRequestException catch (e) {
      recordProblem(_lookupFailed, e, path: _operators.first.path);
      return null;
    }
  }
}

/// A hierarchy, with the renames of its members.
final class _Renamable {
  const _Renamable(this.hierarchy, this.renames);

  final OperatorHierarchy hierarchy;
  final List<_Rename> renames;
}

/// The rename of a member: its `operator` keyword becomes [_newName], and
/// spaces replace its name.
final class _Rename {
  const _Rename(this.path, {required this.keyword, required this.name});

  final String path;

  /// The offset of the `operator` keyword in the content on disk.
  final int keyword;

  /// The offsets of the name in the content on disk.
  final ({int start, int end}) name;

  /// The texts that replace the keyword and the name.
  Iterable<({int offset, String text})> get texts => [
    (offset: keyword, text: _newName),
    (offset: name.start, text: ' ' * (name.end - name.start)),
  ];
}

/// The uses of [hierarchy] among [errors], the new errors by file of the
/// [round] that renamed it. In a round of several hierarchies, an error at an
/// operator belongs to the hierarchy with that name, and any other error to
/// each of them.
List<Location> _usesOf(
  OperatorHierarchy hierarchy,
  List<_Renamable> round,
  Map<String, Set<Range>> errors,
  SourceIndex sources,
) => [
  for (final MapEntry(key: path, value: ranges) in errors.entries)
    for (final range in ranges)
      if (sources.textOf(path, range) case final text
          when text == hierarchy.name ||
              round.none((other) => other.hierarchy.name == text))
        .new(uri: File(path).uri.toString(), range: range),
];

/// [renamables] grouped into rounds that rename them together.
///
/// Most hierarchies get a round of their own. After `a + b` fails, the server
/// doesn't know the type of the expression, so the server reports no error at
/// the `*` of `(a + b) * c`, which would hide that use if `*` were renamed in
/// the same round. A comparison such as `a < b` gives a `bool`, though, and no
/// class, mixin, enum or extension type that declares an operator is a
/// supertype of `bool`. So the hierarchies whose members all return `bool`
/// share rounds, one for each name, such as `<` and `>=`, as long as the
/// error of each use covers only the operator, so that its text tells which
/// hierarchy it belongs to.
List<List<_Renamable>> _roundsOf(
  LspClient client,
  List<_Renamable> renamables,
) {
  final shared = <List<_Renamable>>[];
  final own = <List<_Renamable>>[];
  for (final renamable in renamables) {
    final name = renamable.hierarchy.name;
    if (!_errorCoversOnlyTheOperator(name) ||
        !_returnsBool(client, renamable.hierarchy)) {
      own.add([renamable]);
    } else if (shared.firstWhereOrNull(
          (round) => round.none((other) => other.hierarchy.name == name),
        )
        case final round?) {
      round.add(renamable);
    } else {
      shared.add([renamable]);
    }
  }
  return [...own, ...shared];
}

/// Whether the server reports the error of a use of the operator named [name]
/// at the operator alone. The error of `a[i]` covers `[i]`.
bool _errorCoversOnlyTheOperator(String name) => name != '[]' && name != '[]=';

/// Whether every member of [hierarchy] returns `bool`, and no candidate is a
/// member of an extension or an extension type. A member in a file that the
/// server sent no outline for, such as one that the scan skips, counts as
/// returning something else.
bool _returnsBool(LspClient client, OperatorHierarchy hierarchy) =>
    hierarchy.operators.none((operator) => operator.isExtensionMember) &&
    hierarchy.members.every(
      (member) =>
          client
              .cachedOutline(member.uri)
              ?.namedAt(member.range.start)
              ?.node
              .element
              .returnType ==
          'bool',
    );

/// The renames of [members], or `null` when the token before a member's
/// name, apart from comments, is not the `operator` keyword.
Future<List<_Rename>?> _renamesOf(
  LspClient client,
  SourceIndex sources,
  Set<DeclarationName> members,
) async {
  final renames = <_Rename>[];
  for (final member in members) {
    final path = member.path;
    final tokens =
        sources.semanticTokens(path) ??
        await client.semanticTokens(member.uri, sources.lines(path));
    if ((
          tokens.lastCodeBefore(member.range.start),
          sources.offsetsOf(path, member.range),
        )
        case (
          SemanticToken(isKeyword: true, text: 'operator', :final start),
          final name?,
        )) {
      renames.add(
        _Rename(path, keyword: sources.offsetOf(path, start)!, name: name),
      );
    } else {
      return null;
    }
  }
  return renames;
}
