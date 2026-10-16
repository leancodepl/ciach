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
  final renamedFile = File(callsByPath.keys.first).uri;
  // The files whose content on the server differs from the file on disk.
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
    final errorsBefore = _errorKeys(client);
    for (final MapEntry(key: path, value: inFile) in callsByPath.entries) {
      change(path, _withCallsRenamed(sources, path, inFile));
    }
    await client.waitForChangesAnalyzed(renamedFile);
    final errorsByPath = _errorKeys(
      client,
    ).difference(errorsBefore).groupListsBy((error) => error.path);
    // A use can be in a file that ciach doesn't scan, such as one that
    // `--exclude` skips; it needs to be open to be rewritten.
    for (final path in errorsByPath.keys) {
      if (!client.isOpen(File(path).uri)) {
        client.didOpen(File(path).uri, sources.content(path));
      }
    }
    final usesByPath = {
      for (final MapEntry(key: path, value: errors) in errorsByPath.entries)
        if (await _usesAmong(client, path, errors) case final uses
            when uses.isNotEmpty)
          path: uses,
    };

    // Each use becomes `(expression).call`, and the renamed methods get their
    // names back.
    final rewritten = [
      for (final MapEntry(key: path, value: uses) in usesByPath.entries)
        _RewrittenFile.of(sources, path, uses),
    ];
    final rewrittenText = {for (final file in rewritten) file.path: file.text};
    for (final path in {...callsByPath.keys, ...rewrittenText.keys}) {
      change(path, rewrittenText[path] ?? sources.content(path));
    }
    final selected = await _selectedMethods(client, rewritten, concurrency);
    return {
      for (final call in calls)
        if (selected
                .where((selection) => call.isNamedAt(selection.method))
                .map((selection) => selection.use)
                .toList()
            case final uses when uses.isNotEmpty)
          call: uses,
    };
  } finally {
    for (final path in changed) {
      client.didChange(File(path).uri, sources.content(path));
    }
    await client.waitForChangesAnalyzed(renamedFile);
  }
}

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

/// A file whose uses of `call` methods are rewritten as `(use).call`.
final class _RewrittenFile {
  _RewrittenFile._(this.path, this.text, this.explicitCalls);

  /// Wraps each of [uses] in [path]'s content as `(use).call`.
  factory _RewrittenFile.of(
    SourceIndex sources,
    String path,
    List<Range> uses,
  ) {
    final content = sources.content(path);
    final spans = [
      for (final use in uses)
        (
          use: use,
          start: sources.offsetOf(path, use.start)!,
          end: sources.offsetOf(path, use.end)!,
        ),
    ];
    // `(` before each use and `).call` after it, applied from the start. At
    // one offset, the uses that end there close before others open, an inner
    // use (the later start) closes first, and an outer use (the later end)
    // opens first.
    final insertions =
        [
          for (final span in spans) ...[
            (offset: span.start, closes: false, span: span),
            (offset: span.end, closes: true, span: span),
          ],
        ].sorted(
          (a, b) =>
              switch ((a.offset.compareTo(b.offset), a.closes, b.closes)) {
                (0, true, false) => -1,
                (0, false, true) => 1,
                (0, true, true) => b.span.start.compareTo(a.span.start),
                (0, false, false) => b.span.end.compareTo(a.span.end),
                (final order, _, _) => order,
              },
        );
    final text = StringBuffer();
    final callOffsets = <({Range use, int offset})>[];
    var copied = 0;
    for (final (:offset, :closes, span: (:use, start: _, end: _))
        in insertions) {
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
    return ._(path, rewritten, [
      for (final (:use, :offset) in callOffsets)
        (use: use, call: positionIn(lineStarts, offset)),
    ]);
  }

  final String path;

  /// The content with every use wrapped.
  final String text;

  /// Each use in the unchanged content, with the position of the `call` that
  /// wraps it in [text].
  final List<({Range use, Position call})> explicitCalls;
}

/// The method that each inserted `call` in [rewritten] resolves to, with the
/// place of the use in the unchanged file.
Future<List<({Location use, Location method})>> _selectedMethods(
  LspClient client,
  List<_RewrittenFile> rewritten,
  int concurrency,
) async {
  final lookups = [
    for (final file in rewritten)
      for (final (:use, :call) in file.explicitCalls)
        (uri: File(file.path).uri, use: use, call: call),
  ];
  final resolved = await mapPooled(lookups, concurrency, (lookup) async {
    try {
      return (
        lookup: lookup,
        methods: await client.definition(lookup.uri, lookup.call),
      );
    } on LspRequestException {
      // An error that isn't a use of `call` leaves nothing to resolve.
      return (lookup: lookup, methods: const <Location>[]);
    }
  });
  return [
    for (final (:lookup, :methods) in resolved)
      for (final method in methods)
        (
          use: Location(uri: lookup.uri.toString(), range: lookup.use),
          method: method,
        ),
  ];
}
