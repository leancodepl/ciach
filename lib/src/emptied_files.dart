import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lexing.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Deletes the files among [rewritten] (absolute paths `--remove` has just
/// rewritten) that were left with nothing but directives — a `library` line,
/// `import`s, a `part of` — and drops the `import`/`export`/`part` directives
/// that pointed at them from the rest of the package under [rootPath], so
/// nothing is left naming a file that no longer exists.
///
/// Only a file the removal itself emptied is a candidate — by taking its last
/// declaration, or the last `export`/`part` it had left to hand on; one that
/// had nothing to begin with is left alone. Conservative in the usual way — a
/// file that still `export`s or owns `part`s hands something on and stays; a
/// file named in a conditional import (`import 'a.dart' if (dart.library.io)
/// 'b.dart'`) stays, since rewriting that directive is more than dropping it;
/// and a `package:` URI whose package no pubspec under the root claims is taken
/// to mean this file (kept) rather than a foreign one (ignored) whenever the
/// paths line up.
///
/// Returns the deleted files, root-relative, with the files they were unlinked
/// from.
List<DeletedFile> deleteEmptiedFiles(Set<String> rewritten, String rootPath) {
  if (rewritten.isEmpty) {
    return const [];
  }
  final root = p.normalize(p.absolute(rootPath));
  final package = _Package.scan(root);
  final pending = rewritten.map(p.normalize).toSet();
  final deleted = <DeletedFile>[];

  // Dropping the `part 'x.dart';` of a deleted part file, or the one `export`
  // of a barrel, can leave that file with nothing but directives too, so go
  // round until nothing more falls.
  var progressed = true;
  while (progressed) {
    progressed = false;
    for (final path in pending.sorted()) {
      final content = package.content(path);
      if (content == null) {
        pending.remove(path);
        continue;
      }
      if (!_isDirectiveOnly(content)) {
        continue;
      }
      final links = package.linksTo(path);
      if (links == null) {
        // Something still needs the file in a way dropping a line won't fix.
        pending.remove(path);
        continue;
      }
      for (final MapEntry(key: importer, value: spans) in links.entries) {
        package.dropSpans(importer, spans);
        pending.add(importer);
      }
      package.delete(path);
      pending.remove(path);
      deleted.add((
        filePath: relativePosix(path, root),
        unlinkedFrom: [
          for (final importer in links.keys.sorted())
            relativePosix(importer, root),
        ],
      ));
      progressed = true;
    }
  }
  return deleted;
}

/// One `library`, `import` or `part of` statement, possibly several, and
/// nothing else — the shape of a file with no declarations left. Comments are
/// blanked before matching, so a file of nothing but comments is empty too.
final _directiveOnly = RegExp(
  r'''^(?:\s*(?:library\b[^;]*|import\s+r?['"][^;]*|part\s+of\b[^;]*);)*\s*$''',
);

bool _isDirectiveOnly(String content) =>
    _directiveOnly.hasMatch(stripComments(content));

/// A directive statement at the start of a line, through its `;`. Only the
/// three that can name another file matter here, and only with a URI string
/// (a `part of lib.name;` names no file).
final _directive = RegExp(
  r'''^[ \t]*(import|export|part)\s+((?:of\s+)?r?['"][^;]*);''',
  multiLine: true,
);

final _uriLiteral = RegExp(r'''r?(['"])([^'"\n]*)\1''');
final _partOf = RegExp(r'^\s*of\b');
final _conditional = RegExp(r'\bif\s*\(');

/// A `[start, end)` span within a file's content.
typedef _Span = ({int start, int end});

/// How a directive relates to a file: not at all, by naming it in a way that
/// can simply be dropped, or by naming it in a way that cannot.
enum _Link { none, droppable, blocking }

/// The Dart files and pubspecs under the root, with their contents cached and
/// kept current across the rewrites made here.
final class _Package {
  _Package._(this._files, this._libDirByPackage);

  factory _Package.scan(String root) {
    final files = <String>{};
    final libDirByPackage = <String, String>{};
    for (final entity in Directory(
      root,
    ).listSync(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      final absolute = p.normalize(entity.absolute.path);
      if (isInSkippedDir(relativePosix(absolute, root))) {
        continue;
      }
      final name = p.basename(absolute);
      if (name.endsWith('.dart')) {
        files.add(absolute);
      } else if (name == 'pubspec.yaml') {
        if (_pubspecName(absolute) case final package?) {
          libDirByPackage[package] = p.join(p.dirname(absolute), 'lib');
        }
      }
    }
    return _Package._(files, libDirByPackage);
  }

  final Set<String> _files;
  final Map<String, String> _libDirByPackage;
  final _contents = <String, String?>{};

  String? content(String path) {
    if (_contents.containsKey(path)) {
      return _contents[path];
    }
    String? read;
    try {
      read = File(path).readAsStringSync();
    } on Object {
      read = null;
    }
    return _contents[path] = read;
  }

  /// The directives in the other files that name [target], as spans to drop
  /// per file — or `null` when any of them names it in a way that can't be
  /// dropped, so [target] must stay.
  Map<String, List<_Span>>? linksTo(String target) {
    final spans = <String, List<_Span>>{};
    for (final path in _files) {
      if (path == target) {
        continue;
      }
      final source = content(path);
      if (source == null) {
        continue;
      }
      for (final match in _directive.allMatches(stripComments(source))) {
        switch (_link(match, path, target)) {
          case .none:
            break;
          case .blocking:
            return null;
          case .droppable:
            spans.putIfAbsent(path, () => []).add((
              start: match.start,
              end: match.end,
            ));
        }
      }
    }
    return spans;
  }

  _Link _link(RegExpMatch directive, String from, String target) {
    final kind = directive.group(1)!;
    final body = directive.group(2)!;
    var link = _Link.none;
    for (final uri in _uriLiteral.allMatches(body)) {
      final resolved = _resolve(uri.group(2)!, from);
      if (resolved == null) {
        continue;
      }
      if (resolved == target) {
        link = .droppable;
      } else if (resolved == _uncertain &&
          _libPathMatches(uri.group(2)!, target)) {
        return .blocking;
      }
    }
    if (link == .none) {
      return link;
    }
    // A conditional import would need rewriting, not dropping; a `part of`
    // naming the file makes it a library that owns parts, which stays.
    final partOf = kind == 'part' && _partOf.hasMatch(body);
    return partOf || _conditional.hasMatch(body) ? .blocking : link;
  }

  /// Marker for a `package:` URI whose package no pubspec under the root
  /// claims — foreign, or this package without a readable pubspec.
  static const _uncertain = '';

  /// The absolute path [uri] names from the file at [from]: `null` for a
  /// `dart:` or otherwise unresolvable URI, [_uncertain] for an unknown
  /// package.
  String? _resolve(String uri, String from) {
    if (uri.startsWith('package:')) {
      final rest = uri.substring('package:'.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        return null;
      }
      final libDir = _libDirByPackage[rest.substring(0, slash)];
      if (libDir == null) {
        return _uncertain;
      }
      return p.normalize(
        p.joinAll([libDir, ...p.posix.split(rest.substring(slash + 1))]),
      );
    }
    if (uri.contains(':')) {
      return null;
    }
    return p.normalize(p.joinAll([p.dirname(from), ...p.posix.split(uri)]));
  }

  /// Whether the lib-relative path of a `package:` [uri] is where [target]
  /// sits under some `lib/` — the one way an unknown package could be this one.
  static bool _libPathMatches(String uri, String target) {
    final slash = uri.indexOf('/');
    if (slash < 0) {
      return false;
    }
    final libRelative = uri.substring(slash + 1);
    return p.posix.joinAll(p.split(target)).endsWith('/lib/$libRelative');
  }

  /// Removes [spans] (in the file's current content) from the file at [path],
  /// each with the rest of its line when nothing else is on it.
  void dropSpans(String path, List<_Span> spans) {
    final source = content(path);
    if (source == null) {
      return;
    }
    final buffer = StringBuffer();
    var cursor = 0;
    for (final span in spans.sortedBy<num>((s) => s.start)) {
      buffer.write(source.substring(cursor, span.start));
      cursor = _consumeTrailingBlankLine(source, span.end);
    }
    buffer.write(source.substring(cursor));
    final updated = buffer.toString();
    File(path).writeAsStringSync(updated);
    _contents[path] = updated;
  }

  void delete(String path) {
    File(path).deleteSync();
    _files.remove(path);
    _contents[path] = null;
  }
}

final _pubspecNameLine = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true);

String? _pubspecName(String pubspecPath) {
  try {
    return _pubspecNameLine
        .firstMatch(File(pubspecPath).readAsStringSync())
        ?.group(1);
  } on Object {
    return null;
  }
}

/// If nothing but whitespace follows [end] on its line, the offset past the
/// line break — so dropping a directive doesn't leave a blank line behind.
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
