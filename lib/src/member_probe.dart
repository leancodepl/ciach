import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/type_leaks.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;

/// Members of sealed types found used by a `textDocument/definition` lookup at
/// a spelling of their name in the files their type reaches. A lookup on a
/// resolved file is far cheaper than a reference search, which the rest
/// still get, so no finding rests on a lookup.
Future<
  ({List<Candidate> used, List<List<Location>> refs, List<Candidate> rest})
>
probeMembers({
  required LspClient client,
  required SourceIndex sources,
  required TypeLeaks leaks,
  required List<Candidate> members,
  required int concurrency,
}) async {
  final code = <String, String>{};
  final sitesOf = <List<_Site>>[];
  final sites = <_Site>{};
  for (final member in members) {
    final pattern = RegExp(
      '(?<![\\w\$])${RegExp.escape(_spelling(member))}(?![\\w\$])',
    );
    final own = <_Site>[];
    for (final path in leaks.filesFor(member)) {
      final content = code[path] ??= stripComments(sources.content(path));
      for (final match in pattern.allMatches(content)) {
        final position = _positionOf(sources.lineStarts(path), match.start);
        if (path == member.path &&
            member.outline.range.start.atOrBefore(position) &&
            position.atOrBefore(member.outline.range.end)) {
          continue;
        }
        own.add((
          path: path,
          position: position,
          length: match.end - match.start,
        ));
      }
    }
    sitesOf.add(own);
    sites.addAll(own);
  }

  final ordered = sites.toList();
  final targets = await mapPooled(ordered, concurrency, (site) async {
    try {
      return await client.definition(File(site.path).uri, site.position);
    } on LspRequestException {
      return const <Location>[];
    }
  });
  final targetsOf = {
    for (var i = 0; i < ordered.length; i++) ordered[i]: targets[i],
  };

  final used = <Candidate>[];
  final refs = <List<Location>>[];
  final rest = <Candidate>[];
  for (final (i, member) in members.indexed) {
    final hit = sitesOf[i]
        .where(
          (site) => targetsOf[site]!.any((target) => _declares(member, target)),
        )
        .firstOrNull;
    if (hit == null) {
      rest.add(member);
      continue;
    }
    used.add(member);
    refs.add([
      Location(
        uri: File(hit.path).uri.toString(),
        range: Range(
          start: hit.position,
          end: Position(
            line: hit.position.line,
            character: hit.position.character + hit.length,
          ),
        ),
      ),
    ]);
  }
  return (used: used, refs: refs, rest: rest);
}

typedef _Site = ({String path, Position position, int length});

/// How a use of [member] is spelled: the class name for an unnamed
/// constructor.
String _spelling(Candidate member) =>
    switch (member.symbol.declarationName(member.container)) {
      'new' => member.container!,
      final name => name,
    };

bool _declares(Candidate member, Location target) {
  if (SourceIndex.pathOf(target.uri) != member.path) {
    return false;
  }
  final name = member.symbol.selectionRange;
  return name.start.atOrBefore(target.range.start) &&
      target.range.start.atOrBefore(name.end);
}

Position _positionOf(List<int> lineStarts, int offset) {
  var lo = 0;
  var hi = lineStarts.length - 1;
  while (lo < hi) {
    final mid = (lo + hi + 1) >> 1;
    if (lineStarts[mid] <= offset) {
      lo = mid;
    } else {
      hi = mid - 1;
    }
  }
  return Position(line: lo, character: offset - lineStarts[lo]);
}
