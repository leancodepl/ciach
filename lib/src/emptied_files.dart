import 'dart:io';

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/paths.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.remover');

/// Deletes the [rewritten] files (absolute paths) left with only
/// `library`/`import`/`part of` lines, dropping the directives naming them
/// under [rootPath]. One that `export`s, owns a `part`, or sits in a
/// conditional import stays.
List<DeletedFile> deleteEmptiedFiles(Set<String> rewritten, String rootPath) {
  if (rewritten.isEmpty) {
    return const [];
  }
  final root = rootPath.absoluteNormalized;
  final package = _Package.scan(root);
  final pending = rewritten.map(p.normalize).toSet();
  final deleted = <DeletedFile>[];

  // Dropping a `part`/`export` line can empty that file in turn.
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
        pending.remove(path);
        continue;
      }
      for (final MapEntry(key: importer, value: spans) in links.entries) {
        package.dropSpans(importer, spans);
        pending.add(importer);
      }
      package.delete(path);
      pending.remove(path);
      final file = (
        filePath: relativePosix(path, root),
        unlinkedFrom: [
          for (final importer in links.keys.sorted())
            relativePosix(importer, root),
        ],
      );
      deleted.add(file);
      _log.fine(
        file.unlinkedFrom.isEmpty
            ? 'Deleted ${file.filePath}: nothing left but library/import/part-of lines.'
            : 'Deleted ${file.filePath}: nothing left but library/import/part-of lines. Dropped the directives naming it from ${file.unlinkedFrom.join(', ')}.',
      );
      progressed = true;
    }
  }
  return deleted;
}

final _directiveOnly = RegExp(
  r'''^(?:\s*(?:library\b[^;]*|import\s+r?['"][^;]*|part\s+of\b[^;]*);)*\s*$''',
);

bool _isDirectiveOnly(String content) =>
    _directiveOnly.hasMatch(stripComments(content));

/// A directive with a URI string, through its `;`.
final _directive = RegExp(
  r'''^[ \t]*(import|export|part)\s+((?:of\s+)?r?['"][^;]*);''',
  multiLine: true,
);

final _partOf = RegExp(r'^\s*of\b');
final _conditional = RegExp(r'\bif\s*\(');

typedef _Span = ({int start, int end});

enum _Link { none, droppable, blocking }

/// The package's Dart files, contents cached across the rewrites.
final class _Package {
  _Package._(this._files, this._libDirByPackage);

  factory _Package.scan(String root) {
    final tree = scanPackageTree(root);
    return ._(tree.dartFiles, tree.libDirByPackage);
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
    } on FileSystemException {
      read = null;
    }
    return _contents[path] = read;
  }

  /// Spans to drop per file, or `null` when a directive naming [target] can't
  /// be dropped.
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
    for (final uri in uriLiteral.allMatches(body)) {
      final resolved = resolveDartUri(
        uri.namedGroup('uri')!,
        from,
        _libDirByPackage,
      );
      if (resolved == null) {
        continue;
      }
      if (resolved == target) {
        link = .droppable;
      } else if (resolved == unknownPackage &&
          _libPathMatches(uri.namedGroup('uri')!, target)) {
        return .blocking;
      }
    }
    if (link == .none) {
      return link;
    }
    final partOf = kind == 'part' && _partOf.hasMatch(body);
    return partOf || _conditional.hasMatch(body) ? .blocking : link;
  }

  /// Whether an unknown package's [uri] could still mean [target].
  static bool _libPathMatches(String uri, String target) {
    final slash = uri.indexOf('/');
    if (slash < 0) {
      return false;
    }
    final libRelative = uri.substring(slash + 1);
    return p.posix.joinAll(p.split(target)).endsWith('/lib/$libRelative');
  }

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
