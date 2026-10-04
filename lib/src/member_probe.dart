import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/concurrency.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:ciach/src/type_leaks.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Range;

/// Members of sealed types found used by a `textDocument/definition` lookup at
/// a spelling of their name in the files their type reaches, with the use as
/// their one reference. A lookup on a resolved file is far cheaper than a
/// reference search, which the rest still get, so no finding rests on a
/// lookup.
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
  final spelled = <(String, String), List<_Site>>{};
  List<_Site> sitesIn(String path, String name) => spelled[(path, name)] ??= [
    for (final match in RegExp(
      '(?<![\\w\$])${RegExp.escape(name)}(?![\\w\$])',
    ).allMatches(sources.code(path)))
      (
        path: path,
        range: Range(
          start: sources.positionOf(path, match.start),
          end: sources.positionOf(path, match.end),
        ),
      ),
  ];

  final sitesOf = {
    for (final member in members)
      member: [
        for (final path in leaks.filesFor(member))
          for (final site in sitesIn(path, _spelling(member)))
            if (path != member.path ||
                !member.outline.range.contains(site.range.start))
              site,
      ],
  };
  final sites = {
    for (final memberSites in sitesOf.values) ...memberSites,
  }.toList();
  final targets = await mapPooled(sites, concurrency, (site) async {
    try {
      return await client.definition(File(site.path).uri, site.range.start);
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
    final hit = memberSites
        .where((site) => targetsOf[site]!.any((t) => _declares(member, t)))
        .firstOrNull;
    if (hit == null) {
      rest.add(member);
    } else {
      used.add(member);
      refs.add([
        Location(uri: File(hit.path).uri.toString(), range: hit.range),
      ]);
    }
  }
  return (used: used, refs: refs, rest: rest);
}

typedef _Site = ({String path, Range range});

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
