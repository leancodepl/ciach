import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/reachable_types.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;

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
  await mapPooled(
    files.where((path) => !sources.hasSemanticTokens(path)).toList(),
    concurrency,
    (path) async => sources.cacheSemanticTokens(
      path,
      await semanticTokensOrEmpty(client, sources, path),
    ),
  );

  // Where each name is written in code, per file, from the server's tokens.
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
          end: Position(line: token.line, character: token.end),
        ),
      ));
    }
  }

  // The member's name written in files its type reaches, outside its own
  // declaration.
  final mentionsOfMember = {
    for (final member in members)
      member: [
        for (final path in types.filesFor(member))
          for (final mention
              in mentionsByFile[path]![_spelling(member)] ?? const <_Mention>[])
            if (path != member.path ||
                !member.outline.range.contains(mention.range.start))
              mention,
      ],
  };
  final allMentions = {
    for (final mentions in mentionsOfMember.values) ...mentions,
  }.toList();
  final definitions = await mapPooled(allMentions, concurrency, (
    mention,
  ) async {
    try {
      return await client.definition(
        File(mention.path).uri,
        mention.range.start,
      );
    } on LspRequestException {
      // Unresolved, the mention proves nothing; the reference search decides.
      return const <Location>[];
    }
  });
  final definitionsOf = Map.fromIterables(allMentions, definitions);

  final used = <Candidate>[];
  final refs = <List<Location>>[];
  final rest = <Candidate>[];
  for (final MapEntry(key: member, value: mentions)
      in mentionsOfMember.entries) {
    final use = mentions.firstWhereOrNull(
      (mention) => definitionsOf[mention]!.any((t) => _declares(member, t)),
    );
    if (use == null) {
      rest.add(member);
    } else {
      used.add(member);
      refs.add([
        Location(uri: File(use.path).uri.toString(), range: use.range),
      ]);
    }
  }
  return (used: used, refs: refs, rest: rest);
}

/// A place where a name is written.
typedef _Mention = ({String path, Range range});

/// How a use of [member] is spelled: the class name for an unnamed
/// constructor.
String _spelling(Candidate member) =>
    switch (member.symbol.declarationName(member.container)) {
      'new' => member.container!,
      final name => name,
    };

bool _declares(Candidate member, Location target) =>
    SourceIndex.pathOf(target.uri) == member.path &&
    member.symbol.selectionRange.contains(target.range.start);
