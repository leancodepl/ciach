import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/workspace/file_discovery.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The `analysis_options.yaml` files under [root], and every file they
/// `include:`, rewritten without lint rules and analyzer plugins, by path.
///
/// ciach reads no diagnostics, yet the server runs every enabled lint and
/// plugin on every file it analyzes: on a Flutter app with a plugin that is a
/// third of a cold run, and two thirds of the server's memory. Handed to the
/// server as unsaved edits, these leave the files on disk, and what
/// `dart analyze` sees, as they are. Everything else stays, `include:`,
/// `exclude:` and `enable-experiment:` among it, so the server still decides
/// what to analyze and how to parse it. A file with nothing to drop is left
/// out.
Map<String, String> analysisOptionsWithoutLints(String root) {
  final packages = PackageResolver();
  final rewritten = <String, String>{};
  final visited = <String>{};

  // A `package:` include resolves through the packages of the project the
  // chain starts in, as the server resolves it; a relative one, next to the
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
      if (packages.resolve(include, from) case final target?
          when target != unknownPackage) {
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
    // Unreadable, malformed, or with keys JSON can't hold: the server reads
    // it as it is.
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
  final analyzer = options['analyzer'];
  final analyzerPlugins =
      analyzer is Map<String, Object?> && analyzer.containsKey('plugins');
  if (!options.containsKey('linter') &&
      !options.containsKey('plugins') &&
      !analyzerPlugins) {
    return null;
  }
  return {
    for (final MapEntry(:key, :value) in options.entries)
      if (key == 'analyzer' && value is Map<String, Object?>)
        key: {...value}..remove('plugins')
      else if (key != 'linter' && key != 'plugins')
        key: value,
  };
}
