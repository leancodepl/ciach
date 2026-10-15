import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/workspace/file_discovery.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Every `analysis_options.yaml` under [root], and every file it includes,
/// without its lint rules and analyzer plugins, keyed by path.
///
/// ciach reads no warnings, but the analysis server runs every lint rule and
/// plugin on every file. On a Flutter app with a plugin, that takes a third of
/// a cold run and most of the server's memory. ciach sends these files to the
/// server as unsaved edits, so the files on disk don't change and
/// `dart analyze` sees the same options as before. The rest of each file stays,
/// so the server still decides which files to analyze and how to parse them.
/// A file without lint rules or plugins is left out.
Map<String, String> analysisOptionsWithoutLints(String root) {
  final packages = PackageResolver();
  final rewritten = <String, String>{};
  final visited = <String>{};

  // Like the server, resolve a `package:` include with the packages of the
  // project the first file belongs to, and a relative include next to the
  // file that names it.
  void visit(String path, String chainRoot) {
    if (!visited.add(path)) {
      return;
    }
    final options = _read(path);
    if (options == null) {
      return;
    }
    for (final include in _includes(options)) {
      final from = include.startsWith('package:') ? chainRoot : path;
      if (packages.resolve(include, from)
          case (!= unknownPackage && final target)?) {
        visit(target, chainRoot);
      }
    }
    if (_withoutLints(options) case final kept?) {
      rewritten[path] = jsonEncode(kept);
    }
  }

  for (final path in _optionsFilesUnder(root)) {
    visit(path, path);
  }
  return rewritten;
}

/// The `analysis_options.yaml` files under [root], skipping the directories
/// file discovery skips.
Iterable<String> _optionsFilesUnder(String root) sync* {
  final pending = [Directory(root)];
  while (pending.isNotEmpty) {
    final List<FileSystemEntity> entries;
    try {
      entries = pending.removeLast().listSync(followLinks: false);
    } on FileSystemException {
      continue;
    }
    for (final entity in entries) {
      if (entity is Directory) {
        if (!isInSkippedDir(p.basename(entity.path))) {
          pending.add(entity);
        }
      } else if (entity is File &&
          p.basename(entity.path) == 'analysis_options.yaml') {
        yield p.normalize(entity.absolute.path);
      }
    }
  }
}

/// [path] as plain maps and lists; `null` when it can't be read or parsed.
Map<String, Object?>? _read(String path) {
  try {
    final yaml = loadYaml(File(path).readAsStringSync());
    return switch (jsonDecode(jsonEncode(yaml))) {
      final Map<String, Object?> map => map,
      _ => null,
    };
  } on Object {
    // The file can't be read or parsed, or JSON can't hold its keys. The
    // server reads it as it is.
    return null;
  }
}

/// The URIs [options] includes: one, or a list of them.
List<String> _includes(Map<String, Object?> options) =>
    switch (options['include']) {
      final String uri => [uri],
      final List<Object?> uris => uris.whereType<String>().toList(),
      _ => const [],
    };

/// [options] without `linter:`, `plugins:` and `analyzer: plugins:`; `null`
/// when it has none of them.
Map<String, Object?>? _withoutLints(Map<String, Object?> options) {
  final kept = <String, Object?>{
    for (final MapEntry(:key, :value) in options.entries)
      ...switch ((key, value)) {
        ('linter' || 'plugins', _) => const {},
        ('analyzer', final Map<String, Object?> analyzer) => {
          key: {...analyzer}..remove('plugins'),
        },
        _ => {key: value},
      },
  };
  return const DeepCollectionEquality().equals(kept, options) ? null : kept;
}
