/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/workspace/dart_executable.dart';
import 'package:path/path.dart' as p;

import 'package_config.dart';

/// A package named `app` in a new temporary directory, which a test writes
/// files into and resolves with [files].
final class TestPackage {
  /// Creates the package in a directory whose name starts with `ciach_`
  /// and [name], with a `package_config.json` that gives it the language
  /// version [languageVersion], or else 3.10.
  TestPackage(String name, {String? languageVersion})
    : root = Directory.systemTemp.createTempSync('ciach_${name}_').path {
    write(
      '.dart_tool/package_config.json',
      packageConfig({'app': '.'}, languageVersions: {'app': ?languageVersion}),
    );
  }

  /// The directory of the package.
  final String root;

  ResolvedFiles? _files;

  /// The files under [root], resolved with the SDK that runs the tests when
  /// they are first asked for.
  ResolvedFiles get files =>
      _files ??= .new(root, sdkPath: sdkPathOf(findDartExecutable()));

  var _written = 0;

  /// Writes [content] to the file at [path], relative to [root], and returns
  /// its absolute path.
  String write(String path, String content) {
    final absolute = p.join(root, path);
    File(absolute)
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
    return absolute;
  }

  /// Writes each of [files], by its path relative to [root].
  void writeAll(Map<String, String> files) {
    for (final MapEntry(key: path, value: content) in files.entries) {
      write(path, content);
    }
  }

  /// Writes two more packages under [root], each with a package config of
  /// its own: `core`, whose `lib/core.dart` is [core], and `app`, which
  /// depends on `core` and whose `lib/app.dart` is [app].
  void writeCoreAndApp({required String core, required String app}) =>
      writeAll({
        'core/.dart_tool/package_config.json': packageConfig({'core': '.'}),
        'core/pubspec.yaml': 'name: core\n',
        'core/lib/core.dart': core,
        'app/.dart_tool/package_config.json': packageConfig({
          'app': '.',
          'core': '../core',
        }),
        'app/pubspec.yaml': 'name: app\n',
        'app/lib/app.dart': app,
      });

  /// Writes [source] to a new file in the directory [dir] and returns its
  /// absolute path.
  String writeNew(String source, {String dir = 'lib'}) =>
      write(p.join(dir, 'file${_written++}.dart'), source);

  /// Writes [source] to a new file in the directory [dir] and returns the
  /// file as [files] resolves it.
  Future<ResolvedFile> resolveNew(String source, {String dir = 'lib'}) async =>
      (await files.of(writeNew(source, dir: dir)))!;

  /// Ends the analysis and deletes the directory.
  Future<void> dispose() async {
    await _files?.dispose();
    Directory(root).deleteSync(recursive: true);
  }
}
