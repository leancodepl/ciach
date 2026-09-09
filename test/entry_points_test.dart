import 'package:ciach/src/conventions/entry_points.dart';
import 'package:pro_lsp/pro_lsp.dart';
import 'package:test/test.dart';

void main() {
  /// A symbol as the server reports it; the shape is irrelevant to the rules.
  DocumentSymbol symbol(String name, {SymbolKind kind = .function}) {
    const range = Range(
      start: Position(line: 0, character: 0),
      end: Position(line: 0, character: 0),
    );
    return DocumentSymbol(
      name: name,
      kind: kind,
      range: range,
      selectionRange: range,
    );
  }

  group('EntryPoint.project', () {
    test('a bare name matches in any file, whatever the kind', () {
      final rule = EntryPoint.project('bootstrap');

      expect(rule.files, isEmpty);
      expect(rule.matches('lib/a.dart', symbol('bootstrap'), null), isTrue);
      expect(rule.matches('bin/b.dart', symbol('bootstrap'), null), isTrue);
      expect(
        rule.matches('lib/a.dart', symbol('bootstrap', kind: .variable), null),
        isTrue,
      );
      expect(rule.matches('lib/a.dart', symbol('bootstrapped'), null), isFalse);
    });

    test('globs narrow the file, any of them matching', () {
      final rule = EntryPoint.project(
        'registerWith',
        files: ['lib/**_plugin.dart', 'bin/**'],
      );

      expect(
        rule.matches('lib/src/my_plugin.dart', symbol('registerWith'), null),
        isTrue,
      );
      expect(
        rule.matches('bin/tool.dart', symbol('registerWith'), null),
        isTrue,
      );
      expect(
        rule.matches('lib/src/my_helper.dart', symbol('registerWith'), null),
        isFalse,
      );
    });

    test('a qualified name matches a member of that container only', () {
      final rule = EntryPoint.project('MyPlugin.registerWith');
      final member = symbol('registerWith', kind: .method);

      expect(rule.matches('lib/a.dart', member, 'MyPlugin'), isTrue);
      expect(rule.matches('lib/a.dart', member, 'Other'), isFalse);
      expect(rule.matches('lib/a.dart', symbol('registerWith'), null), isFalse);
    });

    test('a bare name never matches a member', () {
      final rule = EntryPoint.project('registerWith');

      expect(
        rule.matches('lib/a.dart', symbol('registerWith', kind: .method), 'P'),
        isFalse,
      );
    });

    test('prints as the name and its files', () {
      expect('${EntryPoint.project('bootstrap')}', 'bootstrap');
      expect(
        '${EntryPoint.project('run', files: ['a/**', 'b/**'])}',
        'run in a/** or b/**',
      );
    });

    test('rejects a name that is not an identifier', () {
      for (final name in ['', 'a-b', '1abc', 'a.b.c', 'a b', 'A.']) {
        expect(
          () => EntryPoint.project(name),
          throwsA(isFormatException(contains('not a declaration name'))),
          reason: "for '$name'",
        );
      }
    });

    test('rejects an invalid glob, naming it', () {
      expect(
        () => EntryPoint.project('x', files: ['lib/[']),
        throwsA(isFormatException(contains("'lib/[' is not a valid glob"))),
      );
    });
  });

  group('built-in conventions', () {
    final rules = EntryPoints(const []);

    test('main is an entry point in every file, but not as a member', () {
      expect(rules.match('bin/app.dart', symbol('main'), null)?.name, 'main');
      expect(rules.match('test/a_test.dart', symbol('main'), null), isNotNull);
      expect(
        rules.match('lib/a.dart', symbol('main', kind: .method), 'Runner'),
        isNull,
      );
    });

    group('testExecutable', () {
      test('in a flutter_test_config.dart at any depth', () {
        for (final path in [
          'test/flutter_test_config.dart',
          'flutter_test_config.dart',
          'integration_test/nested/flutter_test_config.dart',
        ]) {
          final rule = rules.match(path, symbol('testExecutable'), null);
          expect(rule?.name, 'testExecutable', reason: 'for $path');
          expect(rule?.reason, contains('flutter test'));
        }
      });

      test('whatever its shape — the bootstrap calls it regardless', () {
        expect(
          rules.match(
            'test/flutter_test_config.dart',
            symbol('testExecutable', kind: .variable),
            null,
          ),
          isNotNull,
        );
      });

      test('is not exempt in any other file', () {
        for (final path in [
          'test/test_config.dart',
          'test/my_flutter_test_config.dart',
        ]) {
          expect(
            rules.match(path, symbol('testExecutable'), null),
            isNull,
            reason: 'for $path',
          );
        }
      });

      test('is not exempt as a member', () {
        expect(
          rules.match(
            'test/flutter_test_config.dart',
            symbol('testExecutable', kind: .method),
            'Config',
          ),
          isNull,
        );
      });
    });
  });

  test('a project rule is consulted after the built-in ones', () {
    final rules = EntryPoints([
      EntryPoint.project('main', files: ['tool/**']),
    ]);

    expect(
      rules.match('tool/gen.dart', symbol('main'), null)?.reason,
      'the program entry point',
    );
    expect(rules.match('lib/a.dart', symbol('serve'), null), isNull);
    expect(
      EntryPoints([
        EntryPoint.project('serve'),
      ]).match('lib/a.dart', symbol('serve'), null)?.reason,
      contains('entry-points'),
    );
  });
}

/// A [FormatException] whose message matches [message].
Matcher isFormatException(Matcher message) =>
    isA<FormatException>().having((e) => e.message, 'message', message);
