import 'dart:io';

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/packages.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
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

    // The names each library exposes.
    final visible = <String, _Names>{};
    final pending = <(String, _Names)>[
      for (final MapEntry(key: path, value: directives) in libraries.entries)
        if (!directives.isPart &&
            !p.isWithin(p.join(libDirOf[path]!, 'src'), path))
          (path, _Names.all),
    ];
    while (pending.isNotEmpty) {
      final (library, names) = pending.removeLast();
      final merged = visible[library]?.union(names) ?? names;
      if (merged == visible[library]) {
        continue;
      }
      visible[library] = merged;
      for (final export in libraries[library]?.exports ?? const <_Export>[]) {
        for (final target in export.targets) {
          pending.add((
            libraryOf[target] ?? target,
            export.names.intersection(merged),
          ));
        }
      }
    }
    return ._(rootPath, libDirOf.keys.toSet(), libraryOf, visible);
  }

  final String _rootPath;
  final Set<String> _inLib;
  final Map<String, String> _libraryOf;
  final Map<String, _Names> _visible;

  /// Whether another package could import the file at [path]: one under a
  /// package's `lib/`, or anywhere outside the scanned root.
  bool isImportable(String path) =>
      !p.isWithin(_rootPath, path) || _inLib.contains(path);

  bool exposes(String path, String name) {
    final library = _libraryOf[path] ?? path;
    return !isPrivateName(name) && (_visible[library]?.admits(name) ?? false);
  }
}

final _directive = RegExp(
  r'''^[ \t]*(export|part)\s+([^;]*);''',
  multiLine: true,
);

final _show = RegExp(r'\bshow\b([^;]*?)(?=\b(?:show|hide)\b|$)');
final _hide = RegExp(r'\bhide\b([^;]*?)(?=\b(?:show|hide)\b|$)');

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
        names: _Names.parse(body.substring(uris.last.end)),
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

typedef _Export = ({List<String> targets, _Names names});

/// The names a filter lets through: [shown] (all when `null`) less [hidden].
final class _Names {
  const _Names(this.shown, this.hidden);

  /// The `show` and `hide` clauses in [combinators].
  factory _Names.parse(String combinators) {
    Set<String>? clause(RegExp keyword) => keyword
        .firstMatch(combinators)
        ?.let(
          (match) => {
            for (final m in identifierLike.allMatches(match.group(1)!))
              m.group(0)!,
          },
        );
    return all.intersection(_Names(clause(_show), clause(_hide) ?? const {}));
  }

  static const all = _Names(null, {});

  final Set<String>? shown;
  final Set<String> hidden;

  bool admits(String name) =>
      (shown?.contains(name) ?? true) && !hidden.contains(name);

  /// The names both let through.
  _Names intersection(_Names other) => switch ((shown, other.shown)) {
    (null, null) => _Names(null, hidden.union(other.hidden)),
    (final a?, null) => _Names(a.difference(other.hidden), const {}),
    (null, final b?) => _Names(b.difference(hidden), const {}),
    (final a?, final b?) => _Names(a.intersection(b), const {}),
  };

  /// The names either lets through.
  _Names union(_Names other) => switch ((shown, other.shown)) {
    (null, null) => _Names(null, hidden.intersection(other.hidden)),
    (final a?, null) => _Names(null, other.hidden.difference(a)),
    (null, final b?) => _Names(null, hidden.difference(b)),
    (final a?, final b?) => _Names(a.union(b), const {}),
  };

  @override
  bool operator ==(Object other) =>
      other is _Names &&
      const SetEquality<String>().equals(shown, other.shown) &&
      const SetEquality<String>().equals(hidden, other.hidden);

  @override
  int get hashCode => Object.hash(
    const SetEquality<String>().hash(shown),
    const SetEquality<String>().hash(hidden),
  );
}
