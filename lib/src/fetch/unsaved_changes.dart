/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Sends changed copies of files to the analysis server, and reads the errors
/// that the changes cause. The implicit `call` and operator lookups rename a
/// declaration this way, so that each use that the reference search misses
/// becomes an error. The files on disk never change.
library;

import 'dart:io';

import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Diagnostic, Range;

/// The files whose content on the server differs from the files on disk.
final class UnsavedChanges {
  UnsavedChanges(this._client, this._sources)
    : _errorsBefore = _errors(_client);

  final LspClient _client;
  final SourceIndex _sources;

  /// The errors in the files on disk, by file.
  final Map<String, Set<Diagnostic>> _errorsBefore;

  /// The changed files. Sending the content of the file on disk again would
  /// start another analysis of everything that imports it.
  final _changed = <String>{};

  /// Sends [text] as the content of [path].
  void change(String path, String text) {
    _client.didChange(File(path).uri, text);
    if (text == _sources.content(path)) {
      _changed.remove(path);
    } else {
      _changed.add(path);
    }
  }

  /// Sends the content on disk of each changed file that is not in [keep].
  void restoreExcept(Set<String> keep) {
    for (final path in _changed.difference(keep)) {
      change(path, _sources.content(path));
    }
  }

  /// The ranges of the errors that the changes add, by file, once the server
  /// has analyzed them. An error at a declaration's name, such as a class that
  /// no longer implements its interface, is not a use, so it is left out.
  Future<Map<String, Set<Range>>> newErrors() async {
    await _client.waitForChangesAnalyzed();
    final newErrorsByPath = {
      for (final MapEntry(key: path, value: errors) in _errors(_client).entries)
        if (errors.difference(_errorsBefore[path] ?? const {}) case final added
            when added.isNotEmpty)
          path: added,
    };
    // An error can be in a file that ciach doesn't scan, such as one that
    // `--exclude` skips. It has to be open to get an outline.
    for (final path in newErrorsByPath.keys) {
      _client.ensureOpen(File(path).uri, _sources.content(path));
    }
    return Map.fromIterables(
      newErrorsByPath.keys,
      await Future.wait([
        for (final MapEntry(key: path, value: errors)
            in newErrorsByPath.entries)
          _outsideNames(path, errors),
      ]),
    );
  }

  /// Restores every changed file, and waits until the server has analyzed
  /// them, because later stages read their outlines and diagnostics.
  Future<void> restore() async {
    restoreExcept(const {});
    await _client.waitForChangesAnalyzed();
  }

  /// The ranges of [errors] in [path] that are not at a declaration's name.
  Future<Set<Range>> _outsideNames(String path, Set<Diagnostic> errors) async {
    final names = {
      for (final outline in (await _client.outline(File(path).uri)).descendants)
        ?outline.element.range,
    };
    // Two errors can have the same range.
    return errors.map((error) => error.range).whereNot(names.contains).toSet();
  }
}

/// The errors that the server publishes, by file. A use of a renamed
/// declaration is always an error.
Map<String, Set<Diagnostic>> _errors(LspClient client) => {
  for (final MapEntry(key: uri, value: diagnostics)
      in client.diagnostics.entries)
    SourceIndex.pathOf(uri): {
      for (final diagnostic in diagnostics)
        if (diagnostic.severity == .error) diagnostic,
    },
};
