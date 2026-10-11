import 'dart:io';

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/directives.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/log.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/paths.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

final _log = Logger('ciach.remover');

/// Deletes the [paths] (absolute; rewritten, or empty to begin with) left with
/// only `library`/`import`/`part of` directives, dropping the directives naming
/// them under [rootPath]. One that `export`s, owns a `part`, or sits in a
/// conditional import stays.
List<DeletedFile> deleteEmptiedFiles(Set<String> paths, String rootPath) {
  if (paths.isEmpty) {
    return const [];
  }
  final root = rootPath.absoluteNormalized;
  final package = _Package(root);
  final pending = paths.map(p.normalize).toSet();
  final deleted = <DeletedFile>[];

  // Dropping a `part`/`export` line can empty that file in turn.
  var progressed = true;
  while (progressed) {
    progressed = false;
    for (final path in pending.sorted()) {
      if (_deleteIfEmptied(package, path, pending, root) case final file?) {
        deleted.add(file);
        progressed = true;
      }
    }
  }
  return deleted;
}

/// Deletes [path] if nothing but directives is left in it, dropping the
/// directives naming it and queueing their files in [pending]. Settles [path]
/// unless it may yet be emptied.
DeletedFile? _deleteIfEmptied(
  _Package package,
  String path,
  Set<String> pending,
  String root,
) {
  final content = package.content(path);
  if (content == null) {
    pending.remove(path);
    return null;
  }
  if (!isDirectiveOnly(content)) {
    return null;
  }
  final links = package.linksTo(path);
  if (links == null) {
    pending.remove(path);
    return null;
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
      for (final importer in links.keys.sorted()) relativePosix(importer, root),
    ],
  );
  _log.fine(
    [
      'Deleted ${file.filePath}: nothing left but library/import/part-of directives.',
      if (file.unlinkedFrom.isNotEmpty)
        'Dropped the directives naming it from ${file.unlinkedFrom.join(', ')}.',
    ].join(' '),
  );
  return file;
}

final _directiveOnly = RegExp(
  r'''^(?:\s*(?:library\b[^;]*|import\s+r?['"][^;]*|part\s+of\b[^;]*);)*\s*$''',
);

/// What an empty file holds, for reports: what [isDirectiveOnly] admits.
const emptyFileContents =
    'nothing but comments and library, import or part-of directives';

/// Whether [content] has nothing but comments and `library`, `import` or
/// `part of` directives.
bool isDirectiveOnly(String content) =>
    _directiveOnly.hasMatch(stripComments(content));

typedef _Span = ({int start, int end});

enum _Link { none, droppable, blocking }

/// The package's Dart files, contents cached across the rewrites.
final class _Package {
  _Package(String root) : _files = scanPackageTree(root).dartFiles;

  final Set<String> _files;
  final _packages = PackageResolver();
  final _contents = <String, String?>{};
  final _directives = <String, List<Directive>>{};

  String? content(String path) =>
      _contents.putIfAbsent(path, () => readSource(path));

  /// The directives in [path], none when it can't be read.
  List<Directive> directives(String path) => _directives.putIfAbsent(
    path,
    () => content(path)?.let(Directive.allIn).toList() ?? const [],
  );

  /// Spans to drop per file, or `null` when a directive naming [target] can't
  /// be dropped.
  Map<String, List<_Span>>? linksTo(String target) {
    final spans = <String, List<_Span>>{};
    for (final path in _files) {
      if (path == target) {
        continue;
      }
      for (final directive in directives(path)) {
        switch (_link(directive, path, target)) {
          case .none:
            break;
          case .blocking:
            return null;
          case .droppable:
            spans.putIfAbsent(path, () => []).add((
              start: directive.start,
              end: directive.end,
            ));
        }
      }
    }
    return spans;
  }

  _Link _link(Directive directive, String from, String target) {
    var link = _Link.none;
    for (final uri in directive.uris) {
      final resolved = _packages.resolve(uri.namedGroup('uri')!, from);
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
    return directive.isPartOf || directive.isConditional ? .blocking : link;
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
    _directives.remove(path);
  }

  void delete(String path) {
    File(path).deleteSync();
    _files.remove(path);
    _contents[path] = null;
    _directives.remove(path);
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
