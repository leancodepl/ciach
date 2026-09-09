import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lexing.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;
import 'package:yaml/yaml.dart';

/// Symbol kinds whose [DeclarationRange] covers only the declarator (name and
/// initializer), not the shared `final`/`const`/type prefix or the
/// terminating `;` — because the analysis server reports a variable's range
/// as the `VariableDeclaration`, not the whole
/// `VariableDeclarationList`/`FieldDeclaration` statement it lives in.
const _declaratorKinds = <SymbolKind>{.field, .variable, .constant};

/// A `[start, end)` character-offset span within a file's content.
typedef _Span = ({int start, int end});

/// Deletes [declarations] from the files under [rootPath], rewriting each
/// affected file in a single pass.
///
/// Declarations whose range is fully contained within another declaration's
/// range (e.g. a method of a class that is itself unused) are removed once,
/// as part of removing the enclosing declaration. A declarator that shares a
/// statement with other, still-used declarators (e.g. `int a = 1, b = 2;`) is
/// only removed on its own when that can be done unambiguously; otherwise it
/// is left in place rather than risk producing invalid source.
///
/// A file the removal leaves declaring nothing — only comments, whitespace and
/// `library`/`import`/`part of` directives — is deleted rather than rewritten,
/// and every `import`/`export`/`part` directive elsewhere in the package that
/// pointed at it is dropped, so no directive is left resolving to a file that
/// is gone. That can empty a barrel in turn, which is then deleted the same
/// way. A file that still `export`s or has `part`s is not empty and stays.
///
/// Returns what was rewritten, deleted and dropped; see [RemovalResult].
RemovalResult removeDeclarations(
  List<UnusedDeclaration> declarations,
  String rootPath,
) {
  final byFile = <String, List<UnusedDeclaration>>{};
  for (final decl in declarations) {
    // A blocked finding is reported but never auto-removed: deleting it safely
    // would need a source rewrite (e.g. an `if (x case DeadType())` branch), so
    // leave it — and anything coupled to it — entirely alone.
    if (decl.removalBlocked) {
      continue;
    }
    byFile.putIfAbsent(decl.filePath, () => []).add(decl);
    // Coupled removals are extra whole-node spans that must be deleted together
    // with the declaration to keep the source compiling (a dead StatefulWidget's
    // paired `State` subclass, or a dead sealed member's `case` arm), but that
    // are not findings in their own right. Each names its own file — usually the
    // declaration's, but a `case` arm can live elsewhere — so group it under
    // that file. Turn each into a synthetic whole-node declaration so it flows
    // through the normal removal pass and its span merges with the rest.
    for (final coupled in decl.coupledRemovals) {
      final range = coupled.range;
      byFile
          .putIfAbsent(coupled.filePath, () => [])
          .add(
            UnusedDeclaration(
              name: '',
              kind: .class$,
              filePath: coupled.filePath,
              line: range.startLine + 1,
              column: range.startColumn + 1,
              isPrivate: true,
              range: range,
            ),
          );
    }
  }

  final root = p.normalize(p.absolute(rootPath));
  var filesChanged = 0;
  final emptied = <String>[];
  for (final entry in byFile.entries) {
    final file = File(p.joinAll([root, ...p.posix.split(entry.key)]));
    final content = file.readAsStringSync();
    final updated = _removeFromContent(content, entry.value);
    if (updated == content) {
      continue;
    }
    filesChanged++;
    if (_declaresNothing(updated)) {
      emptied.add(file.path);
    } else {
      file.writeAsStringSync(updated);
    }
  }
  final (:deletedFiles, :removedDirectives) = _deleteEmptiedFiles(
    emptied,
    root,
  );
  return RemovalResult(
    filesChanged: filesChanged,
    deletedFiles: deletedFiles,
    removedDirectives: removedDirectives,
  );
}

/// Directive keywords that name another file — the ones to drop when that
/// file is deleted. `part of` also starts with `part`, but names a library,
/// not a file to drop; [_directiveUri] tells them apart.
const _fileDirectives = {'import', 'export', 'part'};

/// Deletes the [emptied] files (absolute paths) and drops the directives that
/// pointed at them from every other Dart file under [root], repeating for any
/// file that is itself left with nothing once its directives are gone (a
/// barrel of only-deleted `export`s, a library of only-deleted `part`s).
({List<String> deletedFiles, List<RemovedDirective> removedDirectives})
_deleteEmptiedFiles(List<String> emptied, String root) {
  if (emptied.isEmpty) {
    return (deletedFiles: const [], removedDirectives: const []);
  }
  final packageName = _packageName(root);
  final deleted = <String>[];
  final removedDirectives = <RemovedDirective>[];
  var pending = emptied;
  while (pending.isNotEmpty) {
    for (final path in pending) {
      File(path).deleteSync();
    }
    deleted.addAll(pending);
    final targets = pending.toSet();
    // A directive naming a file spells out its basename, so a file mentioning
    // none of them has nothing to drop and needn't be tokenized.
    final basenames = {for (final path in targets) p.basename(path)};
    final emptiedNext = <String>[];
    for (final path in _packageDartFiles(root)) {
      final file = File(path);
      final content = file.readAsStringSync();
      if (!basenames.any(content.contains)) {
        continue;
      }
      final (:updated, :dropped) = _dropDirectivesTo(
        content,
        path: path,
        targets: targets,
        root: root,
        packageName: packageName,
      );
      if (dropped.isEmpty) {
        continue;
      }
      final relative = relativePosix(path, root);
      for (final directive in dropped) {
        removedDirectives.add((filePath: relative, directive: directive));
      }
      if (_declaresNothing(updated)) {
        emptiedNext.add(path);
      } else {
        file.writeAsStringSync(updated);
      }
    }
    pending = emptiedNext;
  }
  return (
    deletedFiles: [for (final path in deleted) relativePosix(path, root)]
      ..sort(),
    removedDirectives: removedDirectives,
  );
}

/// Every Dart file under [root] a directive could live in — generated files
/// included, since a `.mocks.dart` imports the sources it mocks — minus the
/// build and tool directories the finder never looks at.
List<String> _packageDartFiles(String root) {
  final discovered = discoverDartFilesSplit(FinderOptions(rootPath: root));
  return [...discovered.candidates, ...discovered.warmOnly];
}

/// The `name` in [root]'s `pubspec.yaml`, which `package:` URIs of the
/// package's own files start with; `null` when there is none to be read.
String? _packageName(String root) {
  try {
    final pubspec = loadYaml(
      File(p.join(root, 'pubspec.yaml')).readAsStringSync(),
    );
    return pubspec is YamlMap && pubspec['name'] is String
        ? pubspec['name'] as String
        : null;
  } on Object {
    return null;
  }
}

/// [content] with every top-level `import`/`export`/`part` directive whose URI
/// resolves to one of [targets] removed, plus the source text of each dropped
/// directive (whitespace collapsed, for a log line).
({String updated, List<String> dropped}) _dropDirectivesTo(
  String content, {
  required String path,
  required Set<String> targets,
  required String root,
  required String? packageName,
}) {
  final tokens = tokenize(content);
  final spans = <_Span>[];
  final dropped = <String>[];
  var depth = 0;
  for (var i = 0; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.isOpener) {
      depth++;
      continue;
    }
    if (token.isCloser) {
      if (depth > 0) {
        depth--;
      }
      continue;
    }
    if (depth != 0 || !token.isWord || !_fileDirectives.contains(token.value)) {
      continue;
    }
    final uri = _directiveUri(content, token.end);
    final terminator = uri == null ? null : _terminatorIndex(tokens, i);
    if (uri == null || terminator == null) {
      continue;
    }
    final target = _resolveDirectiveUri(
      uri,
      importer: path,
      root: root,
      packageName: packageName,
    );
    if (target == null || !targets.contains(target)) {
      continue;
    }
    final end = tokens[terminator].end;
    final lineStart = content.lastIndexOf('\n', token.start) + 1;
    final ownsLine = content.substring(lineStart, token.start).trim().isEmpty;
    spans.add((
      start: ownsLine ? lineStart : token.start,
      end: _consumeTrailingBlankLine(content, end),
    ));
    dropped.add(
      content.substring(token.start, end).replaceAll(RegExp(r'\s+'), ' '),
    );
  }
  if (spans.isEmpty) {
    return (updated: content, dropped: const []);
  }
  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in _mergeSpans(spans)) {
    buffer.write(content.substring(cursor, span.start));
    cursor = span.end;
  }
  buffer.write(content.substring(cursor));
  return (updated: buffer.toString(), dropped: dropped);
}

/// The string literal right after a directive keyword ending at [from] — the
/// URI of an `import`/`export`/`part` — or `null` when something else follows
/// (`part of …`, or `import` used as a plain identifier).
String? _directiveUri(String content, int from) {
  var i = from;
  while (i < content.length && _isWhitespace(content[i])) {
    i++;
  }
  if (i < content.length && content[i] == 'r') {
    i++;
  }
  if (i >= content.length || (content[i] != "'" && content[i] != '"')) {
    return null;
  }
  final quote = content[i];
  final close = content.indexOf(quote, i + 1);
  return close == -1 ? null : content.substring(i + 1, close);
}

/// The absolute path a directive [uri] written in [importer] names, when it is
/// a file of this package: a `package:` URI under [packageName] maps into
/// `lib/`, a relative one resolves against the importing file. Other packages,
/// `dart:` libraries and absolute paths are `null`.
String? _resolveDirectiveUri(
  String uri, {
  required String importer,
  required String root,
  required String? packageName,
}) {
  final parsed = Uri.tryParse(uri);
  if (parsed == null || parsed.hasAbsolutePath) {
    return null;
  }
  switch (parsed.scheme) {
    case 'package':
      final segments = parsed.pathSegments;
      if (packageName == null ||
          segments.length < 2 ||
          segments.first != packageName) {
        return null;
      }
      return p.normalize(p.joinAll([root, 'lib', ...segments.skip(1)]));
    case '':
      if (parsed.pathSegments.isEmpty) {
        return null;
      }
      return p.normalize(
        p.joinAll([p.dirname(importer), ...parsed.pathSegments]),
      );
    default:
      return null;
  }
}

/// Whether [content] declares nothing: only comments, whitespace and the
/// directives a file can carry without contributing code — `library`, `import`
/// and `part of` — each possibly annotated. An `export` or a `part` makes
/// other code reachable, so a file keeping one is not empty.
bool _declaresNothing(String content) {
  final tokens = tokenize(content);
  var i = 0;
  while (i < tokens.length) {
    i = _skipAnnotations(tokens, i);
    if (i >= tokens.length) {
      return false;
    }
    final token = tokens[i];
    final isDirective =
        token.isWord &&
        switch (token.value) {
          'library' || 'import' => true,
          'part' =>
            i + 1 < tokens.length &&
                tokens[i + 1].isWord &&
                tokens[i + 1].value == 'of',
          _ => false,
        };
    if (!isDirective) {
      return false;
    }
    final terminator = _terminatorIndex(tokens, i);
    if (terminator == null) {
      return false;
    }
    i = terminator + 1;
  }
  return true;
}

/// The index just past any `@name`, `@lib.name` or `@name(…)` annotations
/// starting at [from].
int _skipAnnotations(List<Token> tokens, int from) {
  var i = from;
  while (i + 1 < tokens.length &&
      !tokens[i].isWord &&
      tokens[i].value == '@' &&
      tokens[i + 1].isWord) {
    i += 2;
    while (i + 1 < tokens.length &&
        !tokens[i].isWord &&
        tokens[i].value == '.' &&
        tokens[i + 1].isWord) {
      i += 2;
    }
    if (i < tokens.length && !tokens[i].isWord && tokens[i].value == '(') {
      var depth = 0;
      while (i < tokens.length) {
        if (tokens[i].isOpener) {
          depth++;
        } else if (tokens[i].isCloser) {
          depth--;
        }
        i++;
        if (depth == 0) {
          break;
        }
      }
    }
  }
  return i;
}

/// The index of the top-level `;` ending the directive whose keyword is at
/// [keyword], or `null` if none follows.
int? _terminatorIndex(List<Token> tokens, int keyword) {
  var depth = 0;
  for (var i = keyword + 1; i < tokens.length; i++) {
    final token = tokens[i];
    if (token.isOpener) {
      depth++;
    } else if (token.isCloser) {
      depth--;
    } else if (depth == 0 && !token.isWord && token.value == ';') {
      return i;
    }
  }
  return null;
}

String _removeFromContent(String content, List<UnusedDeclaration> decls) {
  final lines = content.split('\n');
  final lineStarts = List<int>.filled(lines.length, 0);
  for (var i = 1; i < lines.length; i++) {
    lineStarts[i] = lineStarts[i - 1] + lines[i - 1].length + 1;
  }
  int offsetOf(int line, int column) => lineStarts[line] + column;

  final declarators = <UnusedDeclaration>[];
  final spans = <_Span>[];
  final enumSpans = <_Span>[];
  for (final decl in decls) {
    if (_declaratorKinds.contains(decl.kind)) {
      declarators.add(decl);
    } else {
      final span = _spanFor(decl, content, lines, offsetOf);
      if (span != null) {
        (decl.isEnumValue ? enumSpans : spans).add(span);
      }
    }
  }
  // Merge each enum's value spans, then drop a separator comma left orphaned
  // when a trailing run of values is removed from a compact single-line enum.
  for (final span in _mergeSpans(enumSpans)) {
    spans.add(_absorbOrphanEnumComma(content, span));
  }
  spans.addAll(_declaratorSpans(declarators, content, lines, offsetOf));

  if (spans.isEmpty) {
    return content;
  }

  final buffer = StringBuffer();
  var cursor = 0;
  for (final span in _mergeSpans(spans)) {
    buffer.write(content.substring(cursor, span.start));
    cursor = span.end;
  }
  buffer.write(content.substring(cursor));
  return buffer.toString();
}

/// Computes the span to delete for an enum value or a "whole-node" kind
/// (class, function, method, property, …) whose [DeclarationRange] already
/// covers the full declaration.
_Span? _spanFor(
  UnusedDeclaration decl,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final range = decl.range;
  final baseStart = offsetOf(range.startLine, range.startColumn);
  final baseEnd = offsetOf(range.endLine, range.endColumn);
  final topLine = _extendedTopLine(range.startLine, lines);

  var start = baseStart;
  var end = baseEnd;

  if (decl.isEnumValue) {
    // Reach up to column 0 to grab the value's own leading doc/annotation
    // lines, but only when it starts its own line: on a compact single-line
    // enum the line above is the enum type's comment, not the value's.
    final prefix = lines[range.startLine].substring(0, range.startColumn);
    final startsOwnLine = prefix.trim().isEmpty;
    final valueStart = !startsOwnLine
        ? baseStart
        : (topLine < range.startLine
              ? offsetOf(topLine, 0)
              : offsetOf(range.startLine, 0));
    (start, end) = _extendEnumValue(
      content,
      valueStart: valueStart,
      baseStart: baseStart,
      baseEnd: baseEnd,
    );
  } else {
    start = topLine < range.startLine ? offsetOf(topLine, 0) : baseStart;
    // A whole-node range that shares its line with other content (unusual,
    // but possible) is left alone rather than risk eating it; otherwise its
    // leading indentation is safe to take too.
    if (start == baseStart) {
      final prefix = lines[range.startLine].substring(0, range.startColumn);
      if (prefix.trim().isEmpty) {
        start = offsetOf(range.startLine, 0);
      }
    }
    // Some whole-node kinds (bodyless constructors, arrow-bodied members)
    // don't include their terminating `;` in the range.
    if (end < content.length && content[end] == ';') {
      end++;
    }
  }

  return (start: start, end: _consumeTrailingBlankLine(content, end));
}

/// Computes the spans to delete for `field`/`variable`/`constant` decls,
/// which share a statement — and possibly a `final`/`const`/type prefix —
/// with any number of sibling declarators.
///
/// Declarators are grouped by the statement's terminating `;`. When every
/// declarator in a statement is present in [decls], the whole statement
/// (prefix, every declarator, and the `;`) is removed as one span; otherwise
/// each targeted declarator is trimmed out of the list individually.
List<_Span> _declaratorSpans(
  List<UnusedDeclaration> decls,
  String content,
  List<String> lines,
  int Function(int line, int column) offsetOf,
) {
  final groups = <int, List<UnusedDeclaration>>{};
  for (final decl in decls) {
    final baseEnd = offsetOf(decl.range.endLine, decl.range.endColumn);
    final statementEnd = _finalStatementEnd(content, baseEnd);
    if (statementEnd == null) {
      // Can't even find where the statement ends; leave it alone.
      continue;
    }
    groups.putIfAbsent(statementEnd, () => []).add(decl);
  }

  int startOf(UnusedDeclaration d) =>
      offsetOf(d.range.startLine, d.range.startColumn);

  final spans = <_Span>[];
  for (final MapEntry(key: statementEnd, value: members) in groups.entries) {
    final sorted = members.sortedBy<num>(startOf);
    final whole = _wholeStatementSpan(
      content,
      lines,
      sorted,
      statementEnd,
      offsetOf,
    );
    if (whole != null) {
      spans.add(whole);
      continue;
    }
    for (final decl in sorted) {
      final span = _partialDeclaratorSpan(decl, content, offsetOf);
      if (span != null) {
        spans.add(span);
      }
    }
  }
  return spans;
}

/// Whether every declarator of the statement ending at [statementEnd] is
/// present in [sortedMembers] (sorted by source position) — verified by
/// checking that nothing but a bare `,` separates consecutive members, that
/// nothing but whitespace follows the last one up to [statementEnd], and
/// that no earlier declarator precedes the first one on its line.
///
/// The last check assumes the statement's type/modifier prefix and its first
/// declarator share a line — true for any `dart format`-formatted source.
_Span? _wholeStatementSpan(
  String content,
  List<String> lines,
  List<UnusedDeclaration> sortedMembers,
  int statementEnd,
  int Function(int line, int column) offsetOf,
) {
  final first = sortedMembers.first;
  final lineStart = offsetOf(first.range.startLine, 0);
  final firstStart = offsetOf(first.range.startLine, first.range.startColumn);
  if (_lastTopLevelComma(content.substring(lineStart, firstStart)) != null) {
    return null;
  }

  for (var i = 0; i < sortedMembers.length - 1; i++) {
    final end = offsetOf(
      sortedMembers[i].range.endLine,
      sortedMembers[i].range.endColumn,
    );
    final nextStart = offsetOf(
      sortedMembers[i + 1].range.startLine,
      sortedMembers[i + 1].range.startColumn,
    );
    if (content.substring(end, nextStart).trim() != ',') {
      return null;
    }
  }

  final last = sortedMembers.last;
  final lastEnd = offsetOf(last.range.endLine, last.range.endColumn);
  if (content.substring(lastEnd, statementEnd).trim().isNotEmpty) {
    return null;
  }

  final topLine = _extendedTopLine(first.range.startLine, lines);
  return (
    start: offsetOf(topLine, 0),
    end: _consumeTrailingBlankLine(content, statementEnd + 1),
  );
}

/// Trims a single declarator out of a statement that has other declarators
/// left over, by dropping one neighboring comma. Returns `null` if the
/// statement's shape can't be confidently resolved.
_Span? _partialDeclaratorSpan(
  UnusedDeclaration decl,
  String content,
  int Function(int line, int column) offsetOf,
) {
  final range = decl.range;
  final lineStart = offsetOf(range.startLine, 0);
  final baseStart = offsetOf(range.startLine, range.startColumn);
  final baseEnd = offsetOf(range.endLine, range.endColumn);

  final beforeText = content.substring(lineStart, baseStart);
  final leadingComma = _lastTopLevelComma(beforeText);
  return switch (_nextTopLevelSeparator(content, baseEnd)) {
    null => null,
    (final commaEnd, ',') => (
      start: leadingComma == null ? baseStart : lineStart + leadingComma + 1,
      end: commaEnd + 1,
    ),
    // Separator is the statement's `;`: drop the now-orphaned leading comma if
    // there is one, leaving the `;` in place; otherwise (a sole declarator,
    // unreachable in practice since `_wholeStatementSpan` catches it first)
    // fall back to the line start.
    (final semicolonEnd, _) => switch (leadingComma) {
      final comma? => (start: lineStart + comma, end: baseEnd),
      null => (start: lineStart, end: semicolonEnd + 1),
    },
  };
}

/// Extends [startLine] upward over contiguous doc-comment/annotation lines
/// (stopping at the first blank line), so a declaration's leading metadata is
/// removed along with it.
int _extendedTopLine(int startLine, List<String> lines) {
  var topLine = startLine;
  while (topLine - 1 >= 0) {
    final trimmed = lines[topLine - 1].trim();
    if (trimmed.isEmpty || !_looksLikeMetadata(trimmed)) {
      break;
    }
    topLine--;
  }
  return topLine;
}

bool _looksLikeMetadata(String trimmedLine) =>
    trimmedLine.startsWith('@') ||
    trimmedLine.startsWith('//') ||
    trimmedLine.startsWith('/*') ||
    trimmedLine.startsWith('*') ||
    trimmedLine.endsWith('*/');

/// Enum values are comma-separated, not self-terminating: dropping one
/// without also dropping a neighboring comma leaves invalid syntax. Prefers
/// consuming a trailing comma (keeps the shape for the common
/// trailing-comma style); falls back to the leading comma for the last value
/// in a list without one.
(int, int) _extendEnumValue(
  String content, {
  required int valueStart,
  required int baseStart,
  required int baseEnd,
}) {
  final forward = _nextNonWhitespace(content, baseEnd);
  if (forward != null && content[forward] == ',') {
    // Swallow the blank after the comma too, but stop at a line break so a
    // multi-line enum's indentation stays intact.
    return (valueStart, _skipSameLineBlank(content, forward + 1));
  }
  final backward = _previousNonWhitespace(content, valueStart);
  if (backward != null && content[backward] == ',') {
    return (backward, baseEnd);
  }
  return (valueStart, baseEnd);
}

/// Skips spaces and tabs from [from], but never across a line break — used to
/// consume the gap after a removed enum value's comma.
int _skipSameLineBlank(String content, int from) {
  var i = from;
  while (i < content.length && _isSpaceOrTab(content[i])) {
    i++;
  }
  return i;
}

/// Whether [ch] is a space or tab — a blank that stays on the same line.
bool _isSpaceOrTab(String ch) => switch (ch) {
  ' ' || '\t' => true,
  _ => false,
};

/// Drops the separator comma left dangling when a compact single-line enum
/// loses a trailing run of values — when the merged [span] is bracketed on its
/// own line by a leading `,` and a trailing `}`. Otherwise the comma is a real
/// separator and the span is returned unchanged; the same-line guards leave
/// multi-line enums untouched.
_Span _absorbOrphanEnumComma(String content, _Span span) {
  var after = span.end;
  while (after < content.length && _isSpaceOrTab(content[after])) {
    after++;
  }
  if (after >= content.length || content[after] != '}') {
    return span;
  }
  var before = span.start - 1;
  while (before >= 0 && _isSpaceOrTab(content[before])) {
    before--;
  }
  if (before < 0 || content[before] != ',') {
    return span;
  }
  return (start: before, end: span.end);
}

/// Walks forward from [from] through zero or more top-level `,` separators,
/// returning the index of the statement's terminating top-level `;`, or
/// `null` if one can't be found unambiguously.
int? _finalStatementEnd(String content, int from) {
  var pos = from;
  while (true) {
    switch (_nextTopLevelSeparator(content, pos)) {
      case null:
        return null;
      case (final index, ';'):
        return index;
      case (final index, _):
        pos = index + 1;
    }
  }
}

/// The index of the last top-level (not nested in `()`, `[]`, `{}`, or `<>`)
/// comma in [text], or `null` if there isn't one.
int? _lastTopLevelComma(String text) {
  var depth = 0;
  int? last;
  for (var i = 0; i < text.length; i++) {
    switch (text[i]) {
      case '(' || '[' || '{' || '<':
        depth++;
      case ')' || ']' || '}' || '>':
        if (depth > 0) {
          depth--;
        }
      case ',' when depth == 0:
        last = i;
    }
  }
  return last;
}

/// Scans forward from [from] for the first top-level `,` or `;`, treating
/// `(`, `[`, and `{` as nesting (not `<>`: an initializer expression can
/// legitimately contain a `<` comparison). Returns its index and character,
/// or `null` if the scan runs off the end unbalanced or unresolved.
(int, String)? _nextTopLevelSeparator(String content, int from) {
  var depth = 0;
  for (var i = from; i < content.length; i++) {
    final ch = content[i];
    switch (ch) {
      case '(' || '[' || '{':
        depth++;
      case ')' || ']' || '}':
        if (depth == 0) {
          return null;
        }
        depth--;
      case ',' || ';' when depth == 0:
        return (i, ch);
    }
  }
  return null;
}

/// If nothing but whitespace follows [end] on its line, extends it past the
/// line break — so deleting a declaration doesn't leave a blank line behind.
int _consumeTrailingBlankLine(String content, int end) {
  final nextNewline = content.indexOf('\n', end);
  final restOfLine = content.substring(
    end,
    nextNewline == -1 ? content.length : nextNewline,
  );
  if (restOfLine.trim().isNotEmpty) {
    return end;
  }
  return nextNewline == -1 ? content.length : nextNewline + 1;
}

int? _nextNonWhitespace(String content, int from) {
  for (var i = from; i < content.length; i++) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

int? _previousNonWhitespace(String content, int before) {
  for (var i = before - 1; i >= 0; i--) {
    if (!_isWhitespace(content[i])) {
      return i;
    }
  }
  return null;
}

bool _isWhitespace(String ch) => switch (ch) {
  ' ' || '\t' || '\n' || '\r' => true,
  _ => false,
};

List<_Span> _mergeSpans(List<_Span> spans) {
  final merged = <_Span>[];
  for (final span in spans.sortedBy<num>((s) => s.start)) {
    if (merged.isNotEmpty && span.start <= merged.last.end) {
      final last = merged.removeLast();
      merged.add((
        start: last.start,
        end: span.end > last.end ? span.end : last.end,
      ));
    } else {
      merged.add(span);
    }
  }
  return merged;
}
