@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/ciach.dart';
import 'package:ciach/src/log.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'support/package_config.dart';

/// Two packages side by side, neither using its own API: `shared` is imported
/// from outside the analysis, and `app` only by what is inside it.
void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  setUpAll(() {
    root = .systemTemp.createTempSync('ciach_exported_packages_');
    for (final name in ['shared', 'app']) {
      write('$name/.dart_tool/package_config.json', packageConfig({name: '.'}));
      write('$name/pubspec.yaml', '''
name: $name
environment: {sdk: ^3.10.0}
''');
      write('$name/lib/$name.dart', 'void ${name}Api() {}');
      write('$name/lib/src/hidden.dart', 'void ${name}Internals() {}');
    }
    // A workspace root has no API, so no verdict either.
    write('pubspec.yaml', 'name: _');
  });

  tearDownAll(() => root.deleteSync(recursive: true));

  Future<Set<String>> unused(FinderOptions options) async {
    final result = await Ciach(options).run();
    return {for (final d in result.unused) d.name};
  }

  test("by default, every package's exported API is left out", () async {
    expect(await unused(.new(rootPath: root.path)), {
      'sharedInternals',
      'appInternals',
    });
  });

  test("only the listed packages' exported API is left out", () async {
    final lines = <String>[];
    final level = Logger.root.level;
    Logger.root.level = .CONFIG;
    final logging = Logger.root.onRecord
        .where((r) => r.loggerName == 'ciach.finder')
        .listen((r) => lines.add(r.message));
    addTearDown(() {
      Logger.root.level = level;
      return logging.cancel();
    });

    expect(
      await unused(.new(rootPath: root.path, exportedPackages: ['shared'])),
      {'sharedInternals', 'appApi', 'appInternals'},
    );
    expect(
      lines,
      containsAll(const [
        'shared is in `exported-packages`: what other packages can import is left out.',
        'app is not in `exported-packages`: its API is checked.',
      ]),
    );
    expect(lines, isNot(contains(startsWith('The scanned package'))));
  });

  test('none listed checks every API', () async {
    expect(
      await unused(.new(rootPath: root.path, exportedPackages: const [])),
      {'sharedApi', 'sharedInternals', 'appApi', 'appInternals'},
    );
  });
}
