/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/project_config/pigeon.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory package;

  setUp(() {
    package = .systemTemp.createTempSync('ciach_pigeon_test_');
  });

  tearDown(() {
    package.deleteSync(recursive: true);
  });

  void write(String relativePath, String content) {
    File(p.join(package.path, p.joinAll(p.posix.split(relativePath))))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  /// The rules for the package, which depends on [dependencies], as text.
  List<String> rules({
    String path = '',
    Set<String> dependencies = const {'pigeon'},
  }) => [
    for (final rule in pigeonEntryPoints(p.join(package.path, path), (
      name: 'app',
      dependencies: dependencies,
      yaml: null,
    )))
      '$rule',
  ];

  test(
    'finds the input files: the Dart files that import `package:pigeon/pigeon.dart`',
    () {
      write('pubspec.yaml', 'name: app');
      write('pigeons/messages.dart', '''
import 'package:pigeon/pigeon.dart';

@HostApi()
abstract class MessageApi {}
''');
      write('pigeons/events.dart', '''
import "package:pigeon/pigeon.dart" as pigeon;
''');
      write('lib/app.dart', '''
// import 'package:pigeon/pigeon.dart';
const uri = 'package:pigeon/pigeon.dart';
''');
      write('lib/other.dart', "import 'package:pigeon/other.dart';");

      expect(rules(), [
        'declarations that Pigeon reads in pigeons/events.dart or pigeons/messages.dart',
      ]);
    },
  );

  test('leaves the input files of a nested package to that package', () {
    write('pubspec.yaml', 'name: app');
    write('pigeons/messages.dart', "import 'package:pigeon/pigeon.dart';");
    write('plugin/pubspec.yaml', 'name: plugin');
    write(
      'plugin/pigeons/messages.dart',
      "import 'package:pigeon/pigeon.dart';",
    );

    expect(rules(), [
      'declarations that Pigeon reads in pigeons/messages.dart',
    ]);
    expect(rules(path: 'plugin'), [
      'declarations that Pigeon reads in pigeons/messages.dart',
    ]);
  });

  test('a package without a Pigeon input file has no rule', () {
    write('pubspec.yaml', 'name: app');
    write('lib/app.dart', 'class App {}');

    expect(rules(), isEmpty);
  });

  test('a package that does not depend on `pigeon` has no rule', () {
    write('pubspec.yaml', 'name: app');
    write('pigeons/messages.dart', "import 'package:pigeon/pigeon.dart';");

    expect(rules(dependencies: {'meta'}), isEmpty);
  });
}
