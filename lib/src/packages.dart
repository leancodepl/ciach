import 'dart:io';

import 'package:ciach/src/extensions.dart';
import 'package:ciach/src/file_discovery.dart';
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

final uriLiteral = RegExp(r'''r?(?<quote>['"])(?<uri>[^'"\n]*)\k<quote>''');

/// What [PackageResolver.resolve] returns for a `package:` URI no package
/// config lists.
const unknownPackage = '';

/// Resolves URIs as Dart does: `package:` ones through the
/// `.dart_tool/package_config.json` nearest the file that names them.
final class PackageResolver {
  final _configByDir = <String, PackageConfig?>{};

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

  String? _packagePath(Uri uri, String from) => _configOf(
    p.dirname(from),
  )?.resolve(uri)?.let((file) => p.normalize(file.toFilePath()));

  /// The package config of [dir]: its own, or its nearest ancestor's, as in a
  /// pub workspace.
  PackageConfig? _configOf(String dir) {
    if (_configByDir.containsKey(dir)) {
      return _configByDir[dir];
    }
    final file = File(p.join(dir, '.dart_tool', 'package_config.json'));
    final parent = p.dirname(dir);
    return _configByDir[dir] = file.existsSync()
        ? _read(file)
        : (parent == dir ? null : _configOf(parent));
  }

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
