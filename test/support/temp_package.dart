/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'package_config.dart';

/// Writes a package named [name] with [files], by their paths in the package,
/// to a directory that is deleted after the test, and returns the directory.
/// The package needs no `pub get`.
Directory writeTempPackage(String name, Map<String, String> files) {
  final root = Directory.systemTemp.createTempSync('ciach_${name}_');
  addTearDown(() => root.deleteSync(recursive: true));
  for (final MapEntry(key: path, value: contents) in {
    '.dart_tool/package_config.json': packageConfig({name: '.'}),
    'pubspec.yaml':
        '''
name: $name
environment: {sdk: ^3.13.0}
''',
    ...files,
  }.entries) {
    File(p.join(root.path, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(contents);
  }
  return root;
}
