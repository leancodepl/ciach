import 'dart:io';

import 'package:ciach/src/cached_map.dart';
import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/plural.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:collection/collection.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// The Dart files under a root, and the `lib/` of every package there.
typedef PackageTree = ({Set<String> dartFiles, Set<String> libDirs});

/// Walks [root], never entering a skipped directory. Paths are absolute and
/// normalized.
PackageTree scanPackageTree(String root) {
  final files = _filesUnder(Directory(root));
  return (
    dartFiles: {
      for (final file in files)
        if (file.endsWith('.dart')) file,
    },
    libDirs: {
      for (final file in files)
        if (p.basename(file) == 'pubspec.yaml') p.join(p.dirname(file), 'lib'),
    },
  );
}

/// Every file under [dir], never entering a skipped directory.
List<String> _filesUnder(Directory dir) => [
  for (final entity in dir.listSync(followLinks: false))
    if (entity is Directory && !isInSkippedDir(p.basename(entity.path)))
      ..._filesUnder(entity)
    else if (entity is File)
      p.normalize(entity.absolute.path),
];

/// The text of the file at [path]; `null` when it cannot be read.
String? readSource(String path) {
  try {
    return File(path).readAsStringSync();
  } on FileSystemException {
    return null;
  }
}

final uriLiteral = RegExp(r'''r?(?<quote>['"])(?<uri>[^'"\n]*)\k<quote>''');

/// What [PackageResolver.resolve] returns for a `package:` URI no package
/// config lists.
const unknownPackage = '';

/// Resolves URIs as Dart does: `package:` ones through the
/// `.dart_tool/package_config.json` nearest the file that names them.
final class PackageResolver {
  late final _configByDir = CachedMap<String, PackageConfig?>(_findConfig);
  late final _packageRootByDir = CachedMap<String, String?>(_findPackageRoot);

  /// [uri], written in [from], as an absolute path; [unknownPackage] for a
  /// package [from]'s config doesn't list; `null` for any other scheme.
  String? resolve(String uri, String from) => switch (Uri.tryParse(uri)) {
    Uri(scheme: 'package', pathSegments: [_, _, ...]) && final parsed =>
      _packagePath(parsed, from) ?? unknownPackage,
    Uri(scheme: '') && final parsed => p.normalize(
      p.join(p.dirname(from), p.fromUri(parsed)),
    ),
    _ => null,
  };

  String? _packagePath(Uri uri, String from) =>
      configOf(p.dirname(from))?.resolve(uri)?.toFilePath().let(p.normalize);

  /// The package config of [dir]: its own, or its nearest ancestor's, as in a
  /// pub workspace.
  PackageConfig? configOf(String dir) => _configByDir[dir];

  PackageConfig? _findConfig(String dir) {
    final file = _configFile(dir);
    final parent = p.dirname(dir);
    return file.existsSync()
        ? _read(file)
        : (parent == dir ? null : configOf(parent));
  }

  /// The root of the package that contains [dir], or `null` if there is none.
  ///
  /// The root is the nearest directory at or above [dir] with a
  /// `pubspec.yaml`.
  String? packageRootOf(String dir) => _packageRootByDir[dir];

  String? _findPackageRoot(String dir) {
    final parent = p.dirname(dir);
    return File(p.join(dir, 'pubspec.yaml')).existsSync()
        ? dir
        : (parent == dir ? null : packageRootOf(parent));
  }

  /// Whether `pub get` has run for the package at [root].
  ///
  /// This is true if the package has its own package config. It is also true
  /// if the package is a workspace member and the workspace's package config
  /// lists it. A parent package's config doesn't count, because it doesn't
  /// include this package's dev_dependencies.
  bool isResolved(String root) =>
      _configFile(root).existsSync() || _isListedWorkspaceMember(root);

  bool _isListedWorkspaceMember(String root) =>
      readYamlMap(p.join(root, 'pubspec.yaml'))?['resolution'] == 'workspace' &&
      (configOf(p.dirname(root))?.packages.any(
            (package) => p.equals(package.root.toFilePath(), root),
          ) ??
          false);

  static File _configFile(String dir) =>
      .new(p.join(dir, '.dart_tool', 'package_config.json'));

  /// [file] parsed, skipping malformed entries; `null` when unreadable.
  static PackageConfig? _read(File file) {
    try {
      return PackageConfig.parseBytes(
        file.readAsBytesSync(),
        file.uri,
        onError: (_) {},
      );
    } on FileSystemException {
      return null;
    }
  }
}

/// The roots of the packages under [root] that hold some of [files] and that
/// `pub get` hasn't run for, sorted. Files outside any package are ignored.
List<String> unresolvedPackages(Iterable<String> files, String root) {
  final packages = PackageResolver();
  final roots = {
    for (final file in files)
      if (packages.packageRootOf(p.dirname(file)) case final package?
          when p.equals(root, package) || p.isWithin(root, package))
        package,
  };
  return roots.whereNot(packages.isResolved).toList()..sort();
}

/// Thrown when some scanned packages haven't had `pub get`.
class UnresolvedPackagesException implements Exception {
  const UnresolvedPackagesException(this.packages);

  /// The paths of the packages, relative to the root and separated by `/`.
  /// The root itself is `.`.
  final List<String> packages;

  String get message {
    final these = pluralWord(packages.length, 'this package', 'these packages');
    final they = pluralWord(packages.length, 'it uses', 'they use');
    final them = pluralWord(packages.length, 'it', 'them');
    // Excluding the root would leave nothing to scan.
    final exclude = packages.contains('.')
        ? ''
        : '\nTo skip $them instead, use `--exclude`.';
    return '''
Run `dart pub get` (or `flutter pub get`) in $these first:
${packages.map((package) => '  $package').join('\n')}
Without it, ciach would report code $they as unused.$exclude''';
  }

  @override
  String toString() => message;
}
