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
import 'package:ciach/src/fetch/unsaved_changes.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/source/line_starts.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/concurrency.dart';
import 'package:ciach/src/util/log.dart';
import 'package:ciach/src/util/plural.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;

final _log = Logger('ciach.implicit_calls');

/// The name that replaces `call` while the uses are looked up. It has the
/// length of `call`, so every position after it stays the same.
const _renamed = r'ca$l';

const _lookupFailed =
    'Could not look up the implicit uses of `call` methods; kept them all.';

/// The uses of each of [calls] that the server reports no reference for, by
/// candidate; a `call` method without such a use is left out. `null` when a
/// request to the server failed, so that the uses are unknown.
Future<Map<Candidate, List<Location>>?> findImplicitCalls({
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
  final changes = UnsavedChanges(client, sources);
  try {
    for (final MapEntry(key: path, value: inFile) in callsByPath.entries) {
      changes.change(path, _withCallsRenamed(sources, path, inFile));
    }
    final usesByPath = await changes.newErrors();

    // Each use becomes `(expression).call`, and the renamed methods get their
    // names back.
    final rewritten = {
      for (final MapEntry(key: path, value: uses) in usesByPath.entries)
        if (uses.isNotEmpty) path: _RewrittenFile.of(sources, path, uses),
    };
    for (final MapEntry(key: path, value: file) in rewritten.entries) {
      changes.change(path, file.text);
    }
    changes.restoreExcept(rewritten.keys.toSet());
    final wrappedUses = [
      for (final file in rewritten.values) ...file.wrappedUses,
    ];
    // Unlike `definitionsOrEmpty`, a failed lookup fails the whole step:
    // reading it as no use would report a `call` method that is used.
    final methodsOf = Map.fromIterables(
      wrappedUses,
      await mapPooled(wrappedUses, concurrency, (wrapped) async {
        final methods = await client.definition(wrapped.uri, wrapped.call);
        return [
          for (final method in methods) _inOriginal(method, rewritten, sources),
        ];
      }),
    );
    final usesOf = {
      for (final call in calls)
        if ([
              for (final MapEntry(key: wrapped, value: methods)
                  in methodsOf.entries)
                if (methods.any(call.isNamedAt))
                  Location(uri: wrapped.uri.toString(), range: wrapped.use),
            ]
            case final uses when uses.isNotEmpty)
          call: uses,
    };
    await changes.restore();
    return usesOf;
  } on LspRequestException catch (e) {
    recordProblem(_lookupFailed, e, path: calls.first.path);
    return null;
  } finally {
    // After a failure, the files are restored without waiting for their
    // analysis, which would need another request to the server.
    changes.revert();
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

/// [location] in the unchanged content of its file, when the file is one of
/// [rewritten].
Location _inOriginal(
  Location location,
  Map<String, _RewrittenFile> rewritten,
  SourceIndex sources,
) =>
    rewritten[SourceIndex.pathOf(location.uri)]?.inOriginal(
      location,
      sources,
    ) ??
    location;

/// A use, wrapped as `(use).call` in a rewritten file.
final class _WrappedUse {
  _WrappedUse(this.uri, this.use, this.call);

  /// The file of the use.
  final Uri uri;

  /// The use in the unchanged content.
  final Range use;

  /// The position of the `call` that wraps [use] in the rewritten content.
  final Position call;
}

/// The content of a file with its uses of `call` methods rewritten as
/// `(use).call`.
final class _RewrittenFile {
  _RewrittenFile._(
    this.path,
    this.text,
    this.wrappedUses,
    this._insertions,
    this._lineStarts,
  );

  /// Wraps each of [uses] in [path]'s content as `(use).call`.
  factory _RewrittenFile.of(SourceIndex sources, String path, Set<Range> uses) {
    final content = sources.content(path);
    // `(` before each use and `).call` after it, applied from the start. At
    // one offset, the uses that end there close before others open, and the
    // use whose other end is further away goes on the outside: an inner use
    // closes first, and an outer use opens first.
    final insertions =
        [
          for (final use in uses)
            if ((
                  sources.offsetOf(path, use.start)!,
                  sources.offsetOf(path, use.end)!,
                )
                case (final start, final end)) ...[
              (offset: start, otherEnd: end, closes: false, use: use),
              (offset: end, otherEnd: start, closes: true, use: use),
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
    final inserted = <({int offset, int length})>[];
    var copied = 0;
    for (final (:offset, :closes, :use, otherEnd: _) in insertions) {
      text.write(content.substring(copied, offset));
      copied = offset;
      final insertion = closes ? ').call' : '(';
      if (closes) {
        callOffsets.add((use: use, offset: text.length + ').'.length));
      }
      inserted.add((offset: text.length, length: insertion.length));
      text.write(insertion);
    }
    text.write(content.substring(copied));
    final rewritten = text.toString();
    final lineStarts = lineStartsOf(rewritten);
    return ._(
      path,
      rewritten,
      [
        for (final (:use, :offset) in callOffsets)
          _WrappedUse(File(path).uri, use, positionIn(lineStarts, offset)),
      ],
      inserted,
      lineStarts,
    );
  }

  final String path;

  /// The content with every use wrapped.
  final String text;

  /// The uses, each with the position of the `call` that wraps it in [text].
  final List<_WrappedUse> wrappedUses;

  /// Where [text] has inserted characters, in order.
  final List<({int offset, int length})> _insertions;

  /// The offset at which each line of [text] starts.
  final List<int> _lineStarts;

  /// [location], which is in [text], in the unchanged content.
  Location inOriginal(Location location, SourceIndex sources) {
    Position original(Position position) {
      final offset = _lineStarts[position.line] + position.character;
      final shift = _insertions
          .takeWhile((insertion) => insertion.offset < offset)
          .map((insertion) => insertion.length)
          .sum;
      return sources.positionOf(path, offset - shift);
    }

    return .new(
      uri: location.uri,
      range: .new(
        start: original(location.range.start),
        end: original(location.range.end),
      ),
    );
  }
}
