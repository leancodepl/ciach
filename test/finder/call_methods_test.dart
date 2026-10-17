/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/finder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  final fixturePath = p.join(Directory.current.path, 'example');

  Future<Set<String>> findUnused(List<String> include) async {
    final result = await Ciach(
      .new(rootPath: fixturePath, includeGlobs: include),
    ).run();
    return result.unused.map((d) => d.qualifiedName).toSet();
  }

  const expected = {
    'NeverCalled.call',
    'OnlyCalledFromDeadCode.call',
    'callFromDeadCode',
    'UnusedStaticCall.call',
  };

  test(
    'reports only the `call` methods that no object invocation, tear-off or explicit `.call` uses',
    () async {
      expect(
        await findUnused(const [
          'lib/scenarios/call_methods.dart',
          'lib/scenarios/call_methods_uses.dart',
        ]),
        expected,
      );
    },
  );

  test(
    'counts the implicit uses of a `call` method in a file that is not scanned',
    () async {
      expect(
        await findUnused(const ['lib/scenarios/call_methods.dart']),
        expected,
      );
    },
  );

  test(
    'finds an implicit use that comes before the `call` declaration on its line',
    () async {
      final root = Directory.systemTemp.createTempSync('ciach_call_line_');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String contents) => File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
      write('.dart_tool/package_config.json', packageConfig({'line': '.'}));
      write('pubspec.yaml', '''
name: line
environment: {sdk: ^3.13.0}
''');
      // Wrapping the use as `(A()).call` moves the `call` name after it.
      write('lib/line.dart', '''
class A { int get one => A()(1); int call(int x) => x; }
''');
      write('bin/main.dart', '''
import 'package:line/line.dart';

void main() => print(A().one);
''');

      final result = await Ciach(.new(rootPath: root.path)).run();

      expect(result.unused.map((d) => d.qualifiedName), isEmpty);
    },
  );
}
