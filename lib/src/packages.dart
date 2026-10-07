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
  final dartFiles = <String>{};
  final libDirByPackage = <String, String>{};
  final libDirs = <String>{};
  void walk(Directory dir) {
    for (final entity in dir.listSync(followLinks: false)) {
      final path = p.normalize(entity.absolute.path);
      final name = p.basename(path);
      if (entity is Directory) {
        if (!isInSkippedDir(name)) {
          walk(entity);
        }
      } else if (entity is File) {
        if (name.endsWith('.dart')) {
          dartFiles.add(path);
        } else if (name == 'pubspec.yaml') {
          final libDir = p.join(p.dirname(path), 'lib');
          libDirs.add(libDir);
          if (pubspecName(path) case final package?) {
            libDirByPackage[package] = libDir;
          }
        }
      }
    }
  }

  walk(Directory(root));
  return (
    dartFiles: dartFiles,
    libDirByPackage: libDirByPackage,
    libDirs: libDirs,
  );
}

final uriLiteral = RegExp(r'''r?(?<quote>['"])(?<uri>[^'"\n]*)\k<quote>''');

/// What [resolveDartUri] returns for a `package:` URI no pubspec claims.
const unknownPackage = '';

/// [uri], written in [from], as an absolute path; [unknownPackage] for a
/// package not in [libDirByPackage]; `null` for any other scheme.
String? resolveDartUri(
  String uri,
  String from,
  Map<String, String> libDirByPackage,
) {
  if (uri.startsWith('package:')) {
    final rest = uri.substring('package:'.length);
    final slash = rest.indexOf('/');
    if (slash < 0) {
      return null;
    }
    final libDir = libDirByPackage[rest.substring(0, slash)];
    if (libDir == null) {
      return unknownPackage;
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
