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

  /// Writes [content] to [relativePath] and returns the absolute path.
  String write(String relativePath, String content) {
    final file =
        File(p.join(package.path, p.joinAll(p.posix.split(relativePath))))
          ..createSync(recursive: true)
          ..writeAsStringSync(content);
    return file.path;
  }

  /// The rules for the package with [dartFiles], which depends on
  /// [dependencies], as text.
  List<String> rules(
    List<String> dartFiles, {
    Set<String> dependencies = const {'pigeon'},
  }) => [
    for (final rule in pigeonEntryPoints(package.path, (
      name: 'app',
      dependencies: dependencies,
      yaml: null,
    ), dartFiles))
      '$rule',
  ];

  test(
    'finds the input files: the Dart files that import `package:pigeon/pigeon.dart`',
    () {
      final files = [
        write('pigeons/messages.dart', '''
import 'package:pigeon/pigeon.dart';

@HostApi()
abstract class MessageApi {}
'''),
        write('pigeons/events.dart', '''
import "package:pigeon/pigeon.dart" as pigeon;
'''),
        write('lib/app.dart', '''
// import 'package:pigeon/pigeon.dart';
const uri = 'package:pigeon/pigeon.dart';
'''),
        write('lib/other.dart', "import 'package:pigeon/other.dart';"),
      ];

      expect(rules(files), [
        'declarations that Pigeon reads in pigeons/events.dart or pigeons/messages.dart',
      ]);
    },
  );

  test('a package without a Pigeon input file has no rule', () {
    expect(rules([write('lib/app.dart', 'class App {}')]), isEmpty);
  });

  test('a package that does not depend on `pigeon` has no rule', () {
    expect(
      rules(
        [
          write(
            'pigeons/messages.dart',
            "import 'package:pigeon/pigeon.dart';",
          ),
        ],
        dependencies: {'meta'},
      ),
      isEmpty,
    );
  });
}
