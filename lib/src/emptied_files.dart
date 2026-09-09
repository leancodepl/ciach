import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/lexing.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// Deletes the [rewritten] files (absolute paths) left with nothing but
/// `library`/`import`/`part of` directives, dropping the `import`/`export`/
/// `part` lines naming them elsewhere under [rootPath]. A file that still
/// `export`s or owns `part`s, or is named in a conditional import, stays.
List<DeletedFile> deleteEmptiedFiles(Set<String> rewritten, String rootPath) {
  if (rewritten.isEmpty) {
    return const [];
  }
  final root = p.normalize(p.absolute(rootPath));
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

final _uriLiteral = RegExp(r'''r?(['"])([^'"\n]*)\1''');
final _partOf = RegExp(r'^\s*of\b');
final _conditional = RegExp(r'\bif\s*\(');

typedef _Span = ({int start, int end});

enum _Link { none, droppable, blocking }

/// The package's Dart files, with contents cached across the rewrites here.
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
    final partOf = kind == 'part' && _partOf.hasMatch(body);
    return partOf || _conditional.hasMatch(body) ? .blocking : link;
  }

  /// A `package:` URI no pubspec under the root claims.
  static const _uncertain = '';

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
