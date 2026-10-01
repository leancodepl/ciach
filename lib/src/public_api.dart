import 'dart:io';

import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/paths.dart';
import 'package:path/path.dart' as p;

/// Declarations importable by other packages, read from directives only.
final class PublicApi {
  PublicApi._(this._libraryOf, this._visible);

  factory PublicApi.scan(String rootPath) {
    final libDir = p.join(rootPath, 'lib');
    final package = pubspecName(p.join(rootPath, 'pubspec.yaml'));
    final libraries = <String, _Directives>{};
    final dir = Directory(libDir);
    if (dir.existsSync()) {
      for (final entity in dir.listSync(recursive: true, followLinks: false)) {
        if (entity is! File || !entity.path.endsWith('.dart')) {
          continue;
        }
        final path = p.normalize(entity.absolute.path);
        if (isInSkippedDir(relativePosix(path, rootPath))) {
          continue;
        }
        final String content;
        try {
          content = entity.readAsStringSync();
        } on FileSystemException {
          continue;
        }
        libraries[path] = _Directives.parse(content, path, libDir, package);
      }
    }

    final libraryOf = <String, String>{};
    void own(String library, String file) {
      for (final part in libraries[file]?.parts ?? const <String>[]) {
        if (libraryOf.containsKey(part) || part == library) {
          continue;
        }
        libraryOf[part] = library;
        own(library, part);
      }
    }

    for (final MapEntry(key: path, value: directives) in libraries.entries) {
      if (!directives.isPart) {
        own(path, path);
      }
    }

    final visible = <String, List<_Combinator>>{};
    final pending = <(String, _Combinator)>[
      for (final MapEntry(key: path, value: directives) in libraries.entries)
        if (!directives.isPart &&
            !p.isWithin(p.join(libDir, 'src'), path) &&
            !libraryOf.containsKey(path))
          (path, const .all()),
    ];
    while (pending.isNotEmpty) {
      final (library, combinator) = pending.removeLast();
      final seen = visible.putIfAbsent(library, () => []);
      if (seen.contains(combinator)) {
        continue;
      }
      seen.add(combinator);
      for (final file in [
        library,
        for (final MapEntry(key: part, value: owner) in libraryOf.entries)
          if (owner == library) part,
      ]) {
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
    return ._(libraryOf, visible);
  }

  final Map<String, String> _libraryOf;
  final Map<String, List<_Combinator>> _visible;

  int get libraryCount => _visible.length;

  bool exposes(String path, String name) =>
      _visible[_libraryOf[path] ?? path]?.any((c) => c.admits(name)) ?? false;
}

String? pubspecName(String pubspecPath) {
  try {
    return _pubspecNameLine
        .firstMatch(File(pubspecPath).readAsStringSync())
        ?.group(1);
  } on FileSystemException {
    return null;
  }
}

final _pubspecNameLine = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true);

final _directive = RegExp(
  r'''^[ \t]*(export|part)\s+((?:of\b)?[^;]*);''',
  multiLine: true,
);

final _uriLiteral = RegExp(r'''r?(['"])([^'"\n]*)\1''');
final _word = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

final class _Directives {
  _Directives(this.exports, this.parts, {required this.isPart});

  factory _Directives.parse(
    String content,
    String path,
    String libDir,
    String? package,
  ) {
    final exports = <_Export>[];
    final parts = <String>[];
    var isPart = false;
    for (final match in _directive.allMatches(stripComments(content))) {
      final body = match.group(2)!;
      if (match.group(1) == 'part') {
        if (body.startsWith('of')) {
          isPart = true;
        } else if (_uriLiteral.firstMatch(body) case final uri?) {
          if (_resolve(uri.group(2)!, path, libDir, package) case final part?) {
            parts.add(part);
          }
        }
        continue;
      }
      final uris = _uriLiteral.allMatches(body).toList();
      if (uris.isEmpty) {
        continue;
      }
      exports.add((
        targets: [
          for (final uri in uris)
            ?_resolve(uri.group(2)!, path, libDir, package),
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
    String libDir,
    String? package,
  ) {
    if (package != null && uri.startsWith('package:$package/')) {
      return p.normalize(
        p.joinAll([
          libDir,
          ...p.posix.split(uri.substring('package:$package/'.length)),
        ]),
      );
    }
    if (uri.contains(':')) {
      return null;
    }
    return p.normalize(p.joinAll([p.dirname(from), ...p.posix.split(uri)]));
  }
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

  @override
  bool operator ==(Object other) =>
      other is _Combinator &&
      _sameSet(shown, other.shown) &&
      _sameSet(hidden, other.hidden);

  @override
  int get hashCode => Object.hash(
    shown == null ? null : Object.hashAllUnordered(shown!),
    Object.hashAllUnordered(hidden),
  );

  static bool _sameSet(Set<String>? a, Set<String>? b) => a == null || b == null
      ? a == b
      : a.length == b.length && a.containsAll(b);
}
