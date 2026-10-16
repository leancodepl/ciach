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
/// new error marks a possible use. Each of those expressions is then
/// rewritten as `(expression).call`, with the names restored, and a definition
/// lookup on that `call` says which method the use selects. The files on disk
/// never change.
library;

import 'dart:io';

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/fetch/definitions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart'
    show DiagnosticMessage, DiagnosticSeverity, Location, Position, Range;

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
  // The files whose content on the server differs from the file on disk.
  // Sending the content of the file on disk again would start another
  // analysis of everything that imports it.
  final changed = <String>{};
  void change(String path, String text) {
    client.didChange(File(path).uri, text);
    if (text == sources.content(path)) {
      changed.remove(path);
    } else {
      changed.add(path);
    }
  }

  try {
    // A previous lookup may still be restoring its files.
    await client.waitForChangesAnalyzed();
    final errorsBefore = _errors(client);
    for (final MapEntry(key: path, value: inFile) in callsByPath.entries) {
      change(path, _withCallsRenamed(sources, path, inFile));
    }
    await client.waitForChangesAnalyzed();
    final errorsByPath = _errors(
      client,
    ).difference(errorsBefore).groupListsBy((error) => error.path);
    // A use can be in a file that ciach doesn't scan, such as one that
    // `--exclude` skips. It has to be open to be rewritten and to get an
    // outline.
    for (final path in errorsByPath.keys) {
      client.ensureOpen(File(path).uri, sources.content(path));
    }
    final usesByPath = Map.fromIterables(
      errorsByPath.keys,
      await Future.wait([
        for (final MapEntry(key: path, value: errors) in errorsByPath.entries)
          _usesAmong(client, path, errors),
      ]),
    );

    // Each use becomes `(expression).call`, and the renamed methods get their
    // names back.
    final rewritten = {
      for (final MapEntry(key: path, value: uses) in usesByPath.entries)
        if (uses.isNotEmpty) path: _RewrittenFile.of(sources, path, uses),
    };
    for (final path in {...callsByPath.keys, ...rewritten.keys}) {
      change(path, rewritten[path]?.text ?? sources.content(path));
    }
    final lookups = <_Lookup>[
      for (final MapEntry(key: path, value: file) in rewritten.entries)
        for (final (:use, :call) in file.explicitCalls)
          (uri: File(path).uri, use: use, call: call),
    ];
    final methodsOf = await definitionsOrEmpty(
      client,
      lookups,
      (lookup) => (uri: lookup.uri, position: lookup.call),
      concurrency,
    );
    return _usesOf(callsByPath, lookups, methodsOf);
  } finally {
    for (final path in changed.toList()) {
      change(path, sources.content(path));
    }
  }
}

/// A use in the file `uri`, and the position of the `call` that wraps it in
/// the rewritten file.
typedef _Lookup = ({Uri uri, Range use, Position call});

/// The uses that [lookups] found, by the method in [callsByPath] that each
/// one selects; [methodsOf] holds the definitions of each lookup's `call`.
Map<Candidate, List<Location>> _usesOf(
  Map<String, List<Candidate>> callsByPath,
  List<_Lookup> lookups,
  Map<_Lookup, List<Location>> methodsOf,
) =>
    [
          for (final lookup in lookups)
            for (final method in methodsOf[lookup]!)
              if (callsByPath[SourceIndex.pathOf(method.uri)]?.firstWhereOrNull(
                    (call) => call.isNamedAt(method),
                  )
                  case final call?)
                (
                  call: call,
                  use: Location(uri: lookup.uri.toString(), range: lookup.use),
                ),
        ]
        .groupListsBy((found) => found.call)
        .map(
          (call, found) =>
              .new(call, [for (final (:use, call: _) in found) use]),
        );

/// [path]'s content with the names of [calls] replaced by [_renamed].
String _withCallsRenamed(
  SourceIndex sources,
  String path,
  List<Candidate> calls,
) => calls
    .map((call) => sources.offsetOf(path, call.symbol.selectionRange.start)!)
    .fold(
      sources.content(path),
      (text, start) =>
          text.replaceRange(start, start + _renamed.length, _renamed),
    );

/// An error that the server publishes, compared before and after the
/// rename. A use of a removed `call` method is always an error.
typedef _Error = ({String path, Range range, DiagnosticMessage message});

Set<_Error> _errors(LspClient client) => {
  for (final MapEntry(key: uri, value: diagnostics)
      in client.diagnostics.entries)
    for (final diagnostic in diagnostics)
      if (diagnostic.severity == DiagnosticSeverity.error)
        (
          path: SourceIndex.pathOf(uri),
          range: diagnostic.range,
          message: diagnostic.message,
        ),
};

/// The ranges of [errors] that can be uses of a `call` method. An error at a
/// declaration's name, such as a class that no longer implements its
/// interface, is not one, and wrapping that name would break the file.
Future<Set<Range>> _usesAmong(
  LspClient client,
  String path,
  List<_Error> errors,
) async {
  final names = {
    for (final outline in (await client.outline(File(path).uri)).descendants)
      ?outline.element.range,
  };
  // Two errors can have the same range, and one wrap is enough.
  return errors.map((error) => error.range).whereNot(names.contains).toSet();
}

/// The content of a file with its uses of `call` methods rewritten as
/// `(use).call`.
final class _RewrittenFile {
  _RewrittenFile._(this.text, this.explicitCalls);

  /// Wraps each of [uses] in [path]'s content as `(use).call`.
  factory _RewrittenFile.of(SourceIndex sources, String path, Set<Range> uses) {
    final content = sources.content(path);
    // `(` before each use and `).call` after it, applied from the start. At
    // one offset, the uses that end there close before others open, and the
    // use whose other end is further away goes on the outside: an inner use
    // closes first, and an outer use opens first.
    final insertions =
        [
          for (final use in uses) ...[
            (
              offset: sources.offsetOf(path, use.start)!,
              otherEnd: sources.offsetOf(path, use.end)!,
              closes: false,
              use: use,
            ),
            (
              offset: sources.offsetOf(path, use.end)!,
              otherEnd: sources.offsetOf(path, use.start)!,
              closes: true,
              use: use,
            ),
          ],
        ].sorted(
          (a, b) =>
              switch ((a.offset.compareTo(b.offset), a.closes, b.closes)) {
                (0, true, false) => -1,
                (0, false, true) => 1,
                (0, _, _) => b.otherEnd.compareTo(a.otherEnd),
                (final order, _, _) => order,
              },
        );
    final text = StringBuffer();
    final callOffsets = <({Range use, int offset})>[];
    var copied = 0;
    for (final (:offset, :closes, :use, otherEnd: _) in insertions) {
      text.write(content.substring(copied, offset));
      copied = offset;
      if (closes) {
        callOffsets.add((use: use, offset: text.length + ').'.length));
        text.write(').call');
      } else {
        text.write('(');
      }
    }
    text.write(content.substring(copied));
    final rewritten = text.toString();
    final lineStarts = lineStartsOf(rewritten);
    return ._(rewritten, [
      for (final (:use, :offset) in callOffsets)
        (use: use, call: positionIn(lineStarts, offset)),
    ]);
  }

  /// The content with every use wrapped.
  final String text;

  /// Each use in the unchanged content, with the position of the `call` that
  /// wraps it in [text].
  final List<({Range use, Position call})> explicitCalls;
}
