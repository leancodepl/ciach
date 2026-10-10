import 'dart:io';

/// The `name:` in the pubspec at [path].
String? pubspecName(String path) {
  try {
    return _nameLine.firstMatch(File(path).readAsStringSync())?.group(1);
  } on FileSystemException {
    return null;
  }
}

final _nameLine = RegExp(r'^name:\s*([A-Za-z0-9_]+)', multiLine: true);
