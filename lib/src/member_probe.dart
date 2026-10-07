import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/reachable_types.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
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
  // Where each name is written, per file, indexed on first use.
  final mentionsByFile = <String, Map<String, List<_Mention>>>{};
  Map<String, List<_Mention>> findMentions(String path) {
    final mentions = <String, List<_Mention>>{};
    for (final (:name, :offset) in identifierLike(sources.code(path))) {
      (mentions[name] ??= []).add((
        path: path,
        start: offset,
        end: offset + name.length,
      ));
    }
    return mentions;
  }

  Range rangeOf(_Mention mention) => Range(
    start: sources.positionOf(mention.path, mention.start),
    end: sources.positionOf(mention.path, mention.end),
  );

  List<_Mention> mentionsIn(String path, String name) =>
      (mentionsByFile[path] ??= findMentions(path))[name] ?? const [];

  // The member's name written in files its type reaches, outside its own
  // declaration.
  final mentionsOfMember = {
    for (final member in members)
      member: [
        for (final path in types.filesFor(member))
          for (final mention in mentionsIn(path, _spelling(member)))
            if (path != member.path ||
                !member.outline.range.contains(rangeOf(mention).start))
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
        rangeOf(mention).start,
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
        Location(uri: File(use.path).uri.toString(), range: rangeOf(use)),
      ]);
    }
  }
  return (used: used, refs: refs, rest: rest);
}

/// A place where a name is written.
typedef _Mention = ({String path, int start, int end});

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
