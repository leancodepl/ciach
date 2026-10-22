/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Shows changed copies of files to the analysis server, and reads the errors
/// that the changes cause. The files on disk never change.
library;

import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Diagnostic, Range;

/// Runs [lookup], restores every file that it changed, and returns what
/// [lookup] returns.
Future<T> withUnsavedChanges<T>(
  LspClient client,
  SourceIndex sources,
  Future<T> Function(UnsavedChanges changes) lookup,
) async {
  // The server analyzes a change about three times faster with the files
  // closed.
  final closed = client.closeAll();
  final changes = UnsavedChanges._(client, sources);
  final T result;
  try {
    result = await lookup(changes);
  } finally {
    changes.show(const {});
    for (final uri in closed) {
      client.ensureOpen(uri, sources.content(uri.toFilePath()));
    }
  }
  // Later stages read the outlines and errors of the restored files. After
  // an exception, this wait is skipped.
  await client.waitForChangesAnalyzed();
  return result;
}

/// The files whose content on the server differs from the files on disk.
final class UnsavedChanges {
  UnsavedChanges._(this._client, this._sources)
    : _errorsBefore = _errors(_client);

  final LspClient _client;
  final SourceIndex _sources;

  /// The errors in the files on disk, by file.
  final Map<String, Set<Diagnostic>> _errorsBefore;

  /// The changed files. Only these are restored, because sending a file
  /// starts a new analysis of everything that imports it.
  final _changed = <String>{};

  /// Sends [texts], the new content of files by path, to the server. A file
  /// that an earlier call changed and [texts] leaves out gets its content on
  /// disk back.
  void show(Map<String, String> texts) {
    for (final path in _changed.difference(texts.keys.toSet())) {
      _change(path, _sources.content(path));
    }
    texts.forEach(_change);
  }

  void _change(String path, String text) {
    _client.didChange(File(path).uri, text);
    if (text == _sources.content(path)) {
      _changed.remove(path);
    } else {
      _changed.add(path);
    }
  }

  /// Returns the ranges of the new errors that mark uses, by file, once the
  /// server has analyzed the changes.
  Future<Map<String, Set<Range>>> newErrors() async {
    await _client.waitForChangesAnalyzed();
    final newErrorsByPath = {
      for (final MapEntry(key: path, value: errors) in _errors(_client).entries)
        if (errors.difference(_errorsBefore[path] ?? const {}) case final added
            when added.isNotEmpty)
          path: added,
    };
    // An error can be in a file that isn't scanned, such as one that
    // `--exclude` skips. The file must be open to get an outline.
    for (final path in newErrorsByPath.keys) {
      _client.ensureOpen(File(path).uri, _sources.content(path));
    }
    return .fromIterables(
      newErrorsByPath.keys,
      await Future.wait([
        for (final MapEntry(key: path, value: errors)
            in newErrorsByPath.entries)
          _rangesOfUses(path, errors),
      ]),
    );
  }

  /// Returns the ranges of [errors] in [path] that mark uses. An error at a
  /// declaration's name isn't a use: it comes from the declaration itself,
  /// such as a class that no longer implements its interface.
  Future<Set<Range>> _rangesOfUses(String path, Set<Diagnostic> errors) async {
    final names = {
      for (final outline in (await _client.outline(File(path).uri)).descendants)
        ?outline.element.range,
    };
    // Two errors can have the same range.
    return errors.map((error) => error.range).whereNot(names.contains).toSet();
  }
}

/// Returns the errors that the server has published, by file. Only errors
/// count, because a use of a renamed declaration is always an error.
Map<String, Set<Diagnostic>> _errors(LspClient client) => {
  for (final MapEntry(key: uri, value: diagnostics)
      in client.diagnostics.entries)
    SourceIndex.pathOf(uri): {
      for (final diagnostic in diagnostics)
        if (diagnostic.severity == .error) diagnostic,
    },
};
