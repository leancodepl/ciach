/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Finds the uses of `call` methods that the reference search misses: an
/// object invoked like a function (`obj(1)`) and an object used where a
/// function is expected (`int Function(int) f = obj`).
///
/// The analysis server keeps no index entry for these implicit uses, but it
/// still reports a compile error at each of them once the method is gone. So
/// the `call` methods are renamed in unsaved copies of their files, and every
/// new diagnostic marks a possible use. Each of those expressions is then
/// rewritten as `(expression).call`, with the names restored, and a definition
/// lookup on that `call` says which method the use selects. The files on disk
/// never change.
library;

import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show DiagnosticMessage, Location, Position, Range;

final _log = Logger('ciach.implicit_calls');

/// The name that replaces `call` while the uses are looked up. It has the
/// length of `call`, so every position after it stays the same.
const _renamed = r'ca$l';

/// The uses of each of [calls] that the server reports no reference for, by
/// candidate; a `call` method without such a use is left out.
Future<Map<Candidate, List<Location>>> findImplicitCalls({
  required LspClient client,
  required SourceIndex sources,
  required List<Candidate> calls,
  required int concurrency,
}) async {
  if (calls.isEmpty) {
    return const {};
  }
  _log.info(
    'Looking up the implicit uses of ${plural(calls.length, '`call` method', '`call` methods')}…',
  );
  final callsByPath = calls.groupListsBy((call) => call.path);
  final errorsBefore = _errorKeys(client);
  for (final MapEntry(key: path, value: inFile) in callsByPath.entries) {
    client.didChange(File(path).uri, _withCallsRenamed(sources, path, inFile));
  }
  final renamedFile = File(callsByPath.keys.first).uri;
  await client.waitForChangesAnalyzed(renamedFile);
  final errorsByPath = _errorKeys(
    client,
  ).difference(errorsBefore).groupListsBy((error) => error.path);
  final usesByPath = {
    for (final MapEntry(key: path, value: errors) in errorsByPath.entries)
      if (await _usesAmong(client, path, errors) case final uses
          when uses.isNotEmpty)
        path: uses,
  };

  // Each use becomes `(expression).call`, and the renamed methods get their
  // names back.
  final rewritten = {
    for (final MapEntry(key: path, value: uses) in usesByPath.entries)
      path: _withExplicitCalls(sources.content(path), uses),
  };
  for (final path in {...callsByPath.keys, ...rewritten.keys}) {
    client.didChange(
      File(path).uri,
      rewritten[path]?.text ?? sources.content(path),
    );
  }
  final selected = await _selectedCalls(client, rewritten, concurrency);
  for (final path in rewritten.keys) {
    client.didChange(File(path).uri, sources.content(path));
  }
  await client.waitForChangesAnalyzed(renamedFile);

  return {
    for (final call in calls)
      if (selected
              .where((use) => call.isNamedAt(use.target))
              .map((use) => use.site)
              .toList()
          case final uses when uses.isNotEmpty)
        call: uses,
  };
}

/// [path]'s content with the names of [calls] replaced by [_renamed].
String _withCallsRenamed(
  SourceIndex sources,
  String path,
  List<Candidate> calls,
) {
  final content = StringBuffer();
  var copied = 0;
  for (final start
      in calls
          .map(
            (call) => sources.offsetOf(path, call.symbol.selectionRange.start)!,
          )
          .sorted((a, b) => a.compareTo(b))) {
    content
      ..write(sources.content(path).substring(copied, start))
      ..write(_renamed);
    copied = start + _renamed.length;
  }
  return (content..write(sources.content(path).substring(copied))).toString();
}

/// A diagnostic that the server publishes, compared before and after the
/// rename.
typedef _ErrorKey = ({String path, Range range, DiagnosticMessage message});

Set<_ErrorKey> _errorKeys(LspClient client) => {
  for (final MapEntry(key: uri, value: diagnostics)
      in client.diagnostics.entries)
    for (final diagnostic in diagnostics)
      (
        path: SourceIndex.pathOf(uri),
        range: diagnostic.range,
        message: diagnostic.message,
      ),
};

/// The ranges of [errors] that can be uses of a `call` method. An error at a
/// declaration's name, such as an `@override` that no longer overrides
/// anything, is not one, and wrapping that name would break the file.
Future<List<Range>> _usesAmong(
  LspClient client,
  String path,
  List<_ErrorKey> errors,
) async {
  final names = {
    for (final outline in (await client.outline(File(path).uri)).descendants)
      ?outline.element.range,
  };
  return errors.map((error) => error.range).whereNot(names.contains).toList();
}

/// [content] with each of [uses] wrapped as `(use).call`.
({String text, List<({Range site, Position call})> calls}) _withExplicitCalls(
  String content,
  List<Range> uses,
) {
  final starts = lineStartsOf(content);
  int offsetOf(Position position) => starts[position.line] + position.character;
  // `(` before each use and `).call` after it, applied from the start. At the
  // same offset, a `).call` closes an inner use before another `(` opens.
  final insertions =
      [
        for (final use in uses) ...[
          (offset: offsetOf(use.start), text: '(', site: null),
          (offset: offsetOf(use.end), text: ').call', site: use),
        ],
      ].sorted(
        (a, b) => switch (a.offset.compareTo(b.offset)) {
          0 => b.text.length.compareTo(a.text.length),
          final order => order,
        },
      );
  final text = StringBuffer();
  final callOffsets = <({Range site, int offset})>[];
  var copied = 0;
  for (final insertion in insertions) {
    text.write(content.substring(copied, insertion.offset));
    copied = insertion.offset;
    if (insertion.site case final site?) {
      callOffsets.add((site: site, offset: text.length + 2));
    }
    text.write(insertion.text);
  }
  text.write(content.substring(copied));
  final rewritten = text.toString();
  final rewrittenStarts = lineStartsOf(rewritten);
  return (
    text: rewritten,
    calls: [
      for (final (:site, :offset) in callOffsets)
        (site: site, call: positionIn(rewrittenStarts, offset)),
    ],
  );
}

/// The method that each inserted `call` in [rewritten] resolves to, with the
/// place of the use in the unchanged file.
Future<List<({Location site, Location target})>> _selectedCalls(
  LspClient client,
  Map<String, ({String text, List<({Range site, Position call})> calls})>
  rewritten,
  int concurrency,
) async {
  final lookups = [
    for (final MapEntry(key: path, value: (:calls, text: _))
        in rewritten.entries)
      for (final call in calls) (path: path, site: call.site, at: call.call),
  ];
  final targets = await mapPooled(lookups, concurrency, (lookup) async {
    try {
      return await client.definition(File(lookup.path).uri, lookup.at);
    } on LspRequestException {
      // An error that isn't a use of `call` leaves nothing to resolve.
      return const <Location>[];
    }
  });
  return [
    for (final (i, lookup) in lookups.indexed)
      for (final target in targets[i])
        (
          site: Location(
            uri: File(lookup.path).uri.toString(),
            range: lookup.site,
          ),
          target: target,
        ),
  ];
}
