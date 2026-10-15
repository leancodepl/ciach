import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/reference_kinds.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;

/// Finds uses of members by looking up the definition at each mention of
/// their names in the files where they are most likely used, which builds no
/// override hierarchy, unlike a references search.
///
/// One use proves a member used. If it lies in dead code, the member may
/// still be used elsewhere: the settling asks [liveUse] for another, and
/// looks up all its references only if there is none.
final class MemberProbe {
  MemberProbe({
    required LspClient client,
    required SourceIndex sources,
    required int concurrency,
  }) : _client = client,
       _sources = sources,
       _concurrency = concurrency;

  final LspClient _client;
  final SourceIndex _sources;
  final int _concurrency;

  /// Where each probed member's name is written, in the files probed for it.
  final _mentionsOf = <Candidate, List<_Mention>>{};

  /// A mention several members share is looked up once.
  final _definitions = <_Mention, Future<List<Location>>>{};

  /// The members [probe] found used.
  final used = <Candidate>{};

  /// Splits [members] into those a definition lookup finds used, with the
  /// first use it finds, and the rest. A member is looked up in [filesFor]
  /// it.
  Future<
    ({List<Candidate> used, List<List<Location>> refs, List<Candidate> rest})
  >
  probe({
    required Set<String> Function(Candidate member) filesFor,
    required List<Candidate> members,
  }) async {
    final files = {for (final member in members) ...filesFor(member)};
    await _cacheSemanticTokens(_client, _sources, files, _concurrency);
    final mentionsByFile = _mentionsByFile(_sources, files);
    for (final member in members) {
      _mentionsOf[member] = _mentionsIn(
        member,
        filesFor(member),
        mentionsByFile,
      );
    }
    final uses = await mapPooled(
      members,
      _concurrency,
      (member) => _firstUse(member, (_) => false),
    );

    final usedMembers = <Candidate>[];
    final refs = <List<Location>>[];
    final rest = <Candidate>[];
    for (final (i, member) in members.indexed) {
      if (uses[i] case final use?) {
        usedMembers.add(member);
        refs.add([use]);
      } else {
        rest.add(member);
      }
    }
    used.addAll(usedMembers);
    return (used: usedMembers, refs: refs, rest: rest);
  }

  /// A use of [member] among its probed mentions where [isDead] is false, or
  /// `null` when there is none.
  Future<Location?> liveUse(
    Candidate member,
    bool Function(String path, Position position) isDead,
  ) =>
      _firstUse(member, (mention) => isDead(mention.path, mention.range.start));

  Future<Location?> _firstUse(
    Candidate member,
    bool Function(_Mention mention) skip,
  ) async {
    for (final mention in _mentionsOf[member] ?? const <_Mention>[]) {
      if (skip(mention)) {
        continue;
      }
      final targets = await _definitions.putIfAbsent(
        mention,
        () => _definition(_client, mention),
      );
      if (targets.any((t) => _declares(member, t))) {
        return Location(
          uri: File(mention.path).uri.toString(),
          range: mention.range,
        );
      }
    }
    return null;
  }
}

Future<void> _cacheSemanticTokens(
  LspClient client,
  SourceIndex sources,
  Set<String> files,
  int concurrency,
) => mapPooled(
  files.whereNot(sources.hasSemanticTokens).toList(),
  concurrency,
  (path) async => sources.cacheSemanticTokens(
    path,
    await semanticTokensOrEmpty(client, sources, path),
  ),
);

/// Where each name is written in code, per file, from the server's tokens.
Map<String, Map<String, List<_Mention>>> _mentionsByFile(
  SourceIndex sources,
  Set<String> files,
) {
  final mentionsByFile = <String, Map<String, List<_Mention>>>{};
  for (final path in files) {
    final mentions = mentionsByFile[path] = {};
    for (final token in sources.semanticTokens(path)!) {
      // A declaration of a namesake is no use of anything.
      if (sources.isDocLine(path, token.line) ||
          token.modifiers.contains('declaration')) {
        continue;
      }
      (mentions[token.text] ??= []).add((
        path: path,
        range: Range(
          start: token.start,
          end: Position(line: token.line, character: token.end),
        ),
      ));
    }
  }
  return mentionsByFile;
}

/// [member]'s name written in [files], outside its own declaration.
List<_Mention> _mentionsIn(
  Candidate member,
  Set<String> files,
  Map<String, Map<String, List<_Mention>>> mentionsByFile,
) => [
  for (final path in files)
    for (final spelling in _spellings(member))
      if (mentionsByFile[path]![spelling] case final mentions?)
        for (final mention in mentions)
          if (path != member.path ||
              !member.outline.range.contains(mention.range.start))
            mention,
];

/// Where [mention] resolves to.
Future<List<Location>> _definition(LspClient client, _Mention mention) async {
  try {
    return await client.definition(File(mention.path).uri, mention.range.start);
  } on LspRequestException {
    // Unresolved, the mention proves nothing; the reference search decides.
    return const <Location>[];
  }
}

/// A place where a name is written.
typedef _Mention = ({String path, Range range});

/// How a use of [member] is spelled: an unnamed constructor by its class
/// name, or by `new` in `.new()` and `Class.new`.
List<String> _spellings(Candidate member) =>
    switch (member.symbol.declarationName(member.container)) {
      'new' => [member.container!, 'new'],
      final name => [name],
    };

bool _declares(Candidate member, Location target) =>
    SourceIndex.pathOf(target.uri) == member.path &&
    member.symbol.selectionRange.contains(target.range.start);
