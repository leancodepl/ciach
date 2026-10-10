import 'dart:io';

import 'package:ciach/src/file_discovery.dart';
import 'package:ciach/src/pubspec.dart';
import 'package:path/path.dart' as p;

/// The Dart files under a root, and the `lib/` of every package there.
/// `libDirs` also holds those `libDirByPackage` drops: unnamed, or sharing a
/// name.
typedef PackageTree = ({
  Set<String> dartFiles,
  Map<String, String> libDirByPackage,
  Set<String> libDirs,
});

/// Walks [root], never entering a skipped directory. Paths are absolute and
/// normalized.
PackageTree scanPackageTree(String root) {
  final files = _filesUnder(Directory(root));
  final libDirByPackage = <String, String>{};
  final libDirs = <String>{};
  for (final pubspec in files.where((f) => p.basename(f) == 'pubspec.yaml')) {
    final libDir = p.join(p.dirname(pubspec), 'lib');
    libDirs.add(libDir);
    if (pubspecName(pubspec) case final package?) {
      libDirByPackage[package] = libDir;
    }
  }
  return (
    dartFiles: {
      for (final file in files)
        if (file.endsWith('.dart')) file,
    },
    libDirByPackage: libDirByPackage,
    libDirs: libDirs,
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

/// What [resolveDartUri] returns for a `package:` URI no pubspec claims.
const unknownPackage = '';

/// [uri], written in [from], as an absolute path; [unknownPackage] for a
/// package not in [libDirByPackage]; `null` for any other scheme.
String? resolveDartUri(
  String uri,
  String from,
  Map<String, String> libDirByPackage,
) => switch (Uri.tryParse(uri)) {
  Uri(scheme: 'package', pathSegments: [final package, ...final path])
      when path.isNotEmpty =>
    switch (libDirByPackage[package]) {
      final libDir? => p.normalize(p.joinAll([libDir, ...path])),
      null => unknownPackage,
    },
  Uri(scheme: '') && final parsed => p.normalize(
    p.join(p.dirname(from), p.fromUri(parsed)),
  ),
  _ => null,
};
