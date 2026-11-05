import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/definitions.dart';
import 'package:ciach/src/fetch/reachable_types.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/reference_kinds.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Range;

/// Splits [members] into those a definition lookup finds used, with that
/// use, and the rest.
Future<
  ({List<Candidate> used, List<List<Location>> refs, List<Candidate> rest})
>
probeMembers({
  required LspClient client,
  required SourceIndex sources,
  required ReachableTypes types,
  required List<Candidate> members,
  required int concurrency,
}) async {
  final files = {for (final member in members) ...types.filesFor(member)};
  await _cacheSemanticTokens(client, sources, files, concurrency);
  final mentionsByFile = _mentionsByFile(sources, files);
  final mentionsOfMember = {
    for (final member in members)
      member: _mentionsOf(member, types, mentionsByFile),
  };
  final definitionsOf = await definitionsOrEmpty(
    client,
    {for (final mentions in mentionsOfMember.values) ...mentions},
    (mention) => (uri: File(mention.path).uri, position: mention.range.start),
    concurrency,
  );

  final used = <Candidate>[];
  final refs = <List<Location>>[];
  final rest = <Candidate>[];
  for (final MapEntry(key: member, value: mentions)
      in mentionsOfMember.entries) {
    final use = mentions.firstWhereOrNull(
      (mention) => definitionsOf[mention]!.any(member.isNamedAt),
    );
    if (use == null) {
      rest.add(member);
    } else {
      used.add(member);
      refs.add([.new(uri: File(use.path).uri.toString(), range: use.range)]);
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
  (path) => sources.semanticTokensOf(client, path),
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
      if (sources.isDocLine(path, token.line)) {
        continue;
      }
      (mentions[token.text] ??= []).add((
        path: path,
        range: Range(
          start: token.start,
          end: .new(line: token.line, character: token.end),
        ),
      ));
    }
  }
  return mentionsByFile;
}

/// [member]'s name written in files its type reaches, outside its own
/// declaration.
List<_Mention> _mentionsOf(
  Candidate member,
  ReachableTypes types,
  Map<String, Map<String, List<_Mention>>> mentionsByFile,
) => [
  for (final path in types.filesFor(member))
    for (final spelling in _spellings(member))
      if (mentionsByFile[path]![spelling] case final mentions?)
        for (final mention in mentions)
          if (path != member.path ||
              !member.outline.range.contains(mention.range.start))
            mention,
];

/// A place where a name is written.
typedef _Mention = ({String path, Range range});

/// How a use of [member] is spelled: an unnamed constructor by its class
/// name, or by `new` in `.new()` and `Class.new`.
List<String> _spellings(Candidate member) =>
    switch (member.symbol.declarationName(member.container)) {
      'new' => [member.container!, 'new'],
      final name => [name],
    };
