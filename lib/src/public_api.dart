import 'dart:io';

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/symbols.dart';
import 'package:path/path.dart' as p;

/// Declarations importable by other packages, read from directives only.
final class PublicApi {
  PublicApi._(this._rootPath, this._inLib, this._libraryOf, this._visible);

  factory PublicApi.scan(String rootPath) {
    final tree = scanPackageTree(rootPath);
    final libDirOf = <String, String>{};
    for (final path in tree.dartFiles) {
      for (
        var dir = p.dirname(path);
        dir != p.dirname(dir);
        dir = p.dirname(dir)
      ) {
        if (tree.libDirs.contains(dir)) {
          libDirOf[path] = dir;
          break;
        }
      }
    }

    final libraries = <String, _Directives>{};
    for (final path in libDirOf.keys) {
      final String content;
      try {
        content = File(path).readAsStringSync();
      } on FileSystemException {
        continue;
      }
      libraries[path] = _Directives.parse(content, path, tree.libDirByPackage);
    }

    final libraryOf = {
      for (final MapEntry(key: path, value: directives) in libraries.entries)
        if (!directives.isPart)
          for (final part in directives.parts) part: path,
    };

    // The names each library exposes; `null` for all of them.
    final visible = <String, Set<String>?>{};
    final pending = <(String, Set<String>?)>[
      for (final MapEntry(key: path, value: directives) in libraries.entries)
        if (!directives.isPart &&
            !p.isWithin(p.join(libDirOf[path]!, 'src'), path))
          (path, null),
    ];
    while (pending.isNotEmpty) {
      final (library, shown) = pending.removeLast();
      final known = visible.containsKey(library);
      final names = known ? _union(visible[library], shown) : shown;
      if (known && visible[library]?.length == names?.length) {
        continue;
      }
      visible[library] = names;
      for (final export in libraries[library]?.exports ?? const <_Export>[]) {
        final next = switch ((export.shown, names)) {
          (null, final other) || (final other, null) => other,
          (final a?, final b?) => a.intersection(b),
        };
        for (final target in export.targets) {
          pending.add((libraryOf[target] ?? target, next));
        }
      }
    }
    return ._(rootPath, libDirOf.keys.toSet(), libraryOf, visible);
  }

  final String _rootPath;
  final Set<String> _inLib;
  final Map<String, String> _libraryOf;
  final Map<String, Set<String>?> _visible;

  /// Whether another package could import the file at [path]: one under a
  /// package's `lib/`, or anywhere outside the scanned root.
  bool isImportable(String path) =>
      !p.isWithin(_rootPath, path) || _inLib.contains(path);

  bool exposes(String path, String name) {
    final library = _libraryOf[path] ?? path;
    return !isPrivateName(name) &&
        _visible.containsKey(library) &&
        (_visible[library]?.contains(name) ?? true);
  }
}

final _directive = RegExp(
  r'''^[ \t]*(export|part)\s+([^;]*);''',
  multiLine: true,
);

final _word = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

final class _Directives {
  _Directives(this.exports, this.parts, {required this.isPart});

  factory _Directives.parse(
    String content,
    String path,
    Map<String, String> libDirByPackage,
  ) {
    final exports = <_Export>[];
    final parts = <String>[];
    var isPart = false;
    for (final match in _directive.allMatches(stripComments(content))) {
      final body = match.group(2)!;
      if (match.group(1) == 'part') {
        if (body.startsWith('of')) {
          isPart = true;
        } else if (uriLiteral.firstMatch(body) case final uri?) {
          if (_resolve(uri.group(2)!, path, libDirByPackage) case final part?) {
            parts.add(part);
          }
        }
        continue;
      }
      final uris = uriLiteral.allMatches(body).toList();
      if (uris.isEmpty) {
        continue;
      }
      exports.add((
        targets: [
          for (final uri in uris)
            ?_resolve(uri.group(2)!, path, libDirByPackage),
        ],
        shown: _shown(body.substring(uris.last.end)),
      ));
    }
    return .new(exports, parts, isPart: isPart);
  }

  final List<_Export> exports;
  final List<String> parts;

  final bool isPart;

  static String? _resolve(
    String uri,
    String from,
    Map<String, String> libDirByPackage,
  ) => switch (resolveDartUri(uri, from, libDirByPackage)) {
    unknownPackage => null,
    final resolved => resolved,
  };
}

typedef _Export = ({List<String> targets, Set<String>? shown});

Set<String>? _union(Set<String>? a, Set<String>? b) =>
    a == null || b == null ? null : a.union(b);

/// The names a `show` clause in [combinators] lets through; `null` for all.
/// A `hide` is ignored, so hidden names count as exported.
Set<String>? _shown(String combinators) {
  final show = RegExp(
    r'\bshow\b([^;]*?)(?=\bhide\b|$)',
  ).firstMatch(combinators);
  return show == null
      ? null
      : {for (final m in _word.allMatches(show.group(1)!)) m.group(0)!};
}
