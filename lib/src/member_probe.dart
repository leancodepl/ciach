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
  // Each file's identifier-shaped words by name, found in one pass.
  final namesIn = <String, Map<String, List<_Site>>>{};
  Map<String, List<_Site>> index(String path) {
    final names = <String, List<_Site>>{};
    for (final match in identifierLike(sources.code(path))) {
      (names[match.group(0)!] ??= []).add((
        path: path,
        start: match.start,
        end: match.end,
      ));
    }
    return names;
  }

  Range rangeOf(_Site site) => Range(
    start: sources.positionOf(site.path, site.start),
    end: sources.positionOf(site.path, site.end),
  );

  List<_Site> sitesIn(String path, String name) =>
      (namesIn[path] ??= index(path))[name] ?? const [];

  final sitesOf = {
    for (final member in members)
      member: [
        for (final path in types.filesFor(member))
          for (final site in sitesIn(path, _spelling(member)))
            if (path != member.path ||
                !member.outline.range.contains(rangeOf(site).start))
              site,
      ],
  };
  final sites = {
    for (final memberSites in sitesOf.values) ...memberSites,
  }.toList();
  final targets = await mapPooled(sites, concurrency, (site) async {
    try {
      return await client.definition(File(site.path).uri, rangeOf(site).start);
    } on LspRequestException {
      // Unresolved, the site proves nothing; the reference search decides.
      return const <Location>[];
    }
  });
  final targetsOf = Map.fromIterables(sites, targets);

  final used = <Candidate>[];
  final refs = <List<Location>>[];
  final rest = <Candidate>[];
  for (final MapEntry(key: member, value: memberSites) in sitesOf.entries) {
    final hit = memberSites.firstWhereOrNull(
      (site) => targetsOf[site]!.any((t) => _declares(member, t)),
    );
    if (hit == null) {
      rest.add(member);
    } else {
      used.add(member);
      refs.add([
        Location(uri: File(hit.path).uri.toString(), range: rangeOf(hit)),
      ]);
    }
  }
  return (used: used, refs: refs, rest: rest);
}

typedef _Site = ({String path, int start, int end});

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
