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

/// Splits [members] into those a definition lookup finds used, with the
/// first use it finds, and the rest. A member is looked up in [filesFor] it,
/// where it is most likely used.
///
/// One use proves a member used. If it lies in dead code, the member may
/// still be used elsewhere: the settling looks up all its references before
/// calling it dead.
Future<
  ({List<Candidate> used, List<List<Location>> refs, List<Candidate> rest})
>
probeMembers({
  required LspClient client,
  required SourceIndex sources,
  required Set<String> Function(Candidate member) filesFor,
  required List<Candidate> members,
  required int concurrency,
}) async {
  final files = {for (final member in members) ...filesFor(member)};
  await _cacheSemanticTokens(client, sources, files, concurrency);
  final mentionsByFile = _mentionsByFile(sources, files);
  // A mention several members share is looked up once.
  final definitions = <_Mention, Future<List<Location>>>{};
  final uses = await mapPooled(members, concurrency, (member) async {
    for (final mention in _mentionsOf(
      member,
      filesFor(member),
      mentionsByFile,
    )) {
      final targets = await definitions.putIfAbsent(
        mention,
        () => _definition(client, mention),
      );
      if (targets.any((t) => _declares(member, t))) {
        return Location(
          uri: File(mention.path).uri.toString(),
          range: mention.range,
        );
      }
    }
    return null;
  });

  final used = <Candidate>[];
  final refs = <List<Location>>[];
  final rest = <Candidate>[];
  for (final (i, member) in members.indexed) {
    if (uses[i] case final use?) {
      used.add(member);
      refs.add([use]);
    } else {
      rest.add(member);
    }
  }
  return (used: used, refs: refs, rest: rest);
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
List<_Mention> _mentionsOf(
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
