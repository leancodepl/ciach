import 'dart:io';

import 'package:ciach/src/comment_stripping.dart';
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

    final libraryOf = <String, String>{};
    final partsOf = <String, List<String>>{};
    void own(String library, String file) {
      for (final part in libraries[file]?.parts ?? const <String>[]) {
        if (libraryOf.containsKey(part) || part == library) {
          continue;
        }
        libraryOf[part] = library;
        (partsOf[library] ??= []).add(part);
        own(library, part);
      }
    }

    for (final MapEntry(key: path, value: directives) in libraries.entries) {
      if (!directives.isPart) {
        own(path, path);
      }
    }

    final visible = <String, Set<_Combinator>>{};
    final pending = <(String, _Combinator)>[
      for (final MapEntry(key: path, value: directives) in libraries.entries)
        if (!directives.isPart &&
            !p.isWithin(p.join(libDirOf[path]!, 'src'), path) &&
            !libraryOf.containsKey(path))
          (path, const .all()),
    ];
    while (pending.isNotEmpty) {
      final (library, combinator) = pending.removeLast();
      if (!visible.putIfAbsent(library, () => {}).add(combinator)) {
        continue;
      }
      for (final file in [library, ...?partsOf[library]]) {
        for (final export in libraries[file]?.exports ?? const <_Export>[]) {
          for (final target in export.targets) {
            pending.add((
              libraryOf[target] ?? target,
              export.combinator.then(combinator),
            ));
          }
        }
      }
    }
    return ._(rootPath, libDirOf.keys.toSet(), libraryOf, visible);
  }

  final String _rootPath;
  final Set<String> _inLib;
  final Map<String, String> _libraryOf;
  final Map<String, Set<_Combinator>> _visible;

  int get libraryCount => _visible.length;

  /// Whether another package could import the file at [path]: one under a
  /// package's `lib/`, or anywhere outside the scanned root.
  bool isImportable(String path) =>
      !p.isWithin(_rootPath, path) || _inLib.contains(path);

  bool exposes(String path, String name) =>
      !isPrivateName(name) &&
      (_visible[_libraryOf[path] ?? path]?.any((c) => c.admits(name)) ?? false);
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
        combinator: _Combinator.parse(body.substring(uris.last.end)),
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

typedef _Export = ({List<String> targets, _Combinator combinator});

final class _Combinator {
  const _Combinator.all() : shown = null, hidden = const {};

  _Combinator._(this.shown, this.hidden);

  factory _Combinator.parse(String text) {
    var combinator = const _Combinator.all();
    String? clause;
    var names = <String>{};
    void apply() {
      combinator = switch (clause) {
        'show' => combinator.then(._(names, const {})),
        'hide' => combinator.then(._(null, names)),
        _ => combinator,
      };
    }

    for (final word in _word.allMatches(text).map((m) => m.group(0)!)) {
      if (word == 'show' || word == 'hide') {
        apply();
        clause = word;
        names = {};
      } else {
        names.add(word);
      }
    }
    apply();
    return combinator;
  }

  final Set<String>? shown;
  final Set<String> hidden;

  bool admits(String name) =>
      (shown?.contains(name) ?? true) && !hidden.contains(name);

  _Combinator then(_Combinator outer) {
    final hidden = {...this.hidden, ...outer.hidden};
    final shown = switch ((this.shown, outer.shown)) {
      (null, null) => null,
      (final a?, null) => a,
      (null, final b?) => b,
      (final a?, final b?) => a.intersection(b),
    };
    return shown == null
        ? ._(null, hidden)
        : ._(shown.difference(hidden), const {});
  }

  static const _sets = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is _Combinator &&
      _sets.equals(shown, other.shown) &&
      _sets.equals(hidden, other.hidden);

  @override
  int get hashCode =>
      Object.hash(shown == null ? null : _sets.hash(shown), _sets.hash(hidden));
}
