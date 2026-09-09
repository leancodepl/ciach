import 'package:ciach/src/conventions/entry_points.dart';
import 'package:pro_lsp/pro_lsp.dart';
import 'package:test/test.dart';

void main() {
  /// A symbol as the server reports it: [detail] is the parameter list.
  DocumentSymbol symbol(
    String name, {
    SymbolKind kind = .function,
    String? detail,
  }) {
    const range = Range(
      start: Position(line: 0, character: 0),
      end: Position(line: 0, character: 0),
    );
    return DocumentSymbol(
      name: name,
      kind: kind,
      range: range,
      selectionRange: range,
      detail: detail,
    );
  }

  group('EntryPoint.parse', () {
    test('a bare name matches in any file', () {
      final rule = EntryPoint.parse('bootstrap');

      expect(rule.name, 'bootstrap');
      expect(rule.filePattern, isNull);
      expect(rule.matches('lib/a.dart', symbol('bootstrap'), null), isTrue);
      expect(rule.matches('bin/b.dart', symbol('bootstrap'), null), isTrue);
      expect(rule.matches('lib/a.dart', symbol('bootstrapped'), null), isFalse);
    });

    test('a glob narrows the file', () {
      final rule = EntryPoint.parse('lib/**_plugin.dart:registerWith');

      expect(rule.filePattern, 'lib/**_plugin.dart');
      expect(
        rule.matches('lib/src/my_plugin.dart', symbol('registerWith'), null),
        isTrue,
      );
      expect(
        rule.matches('lib/src/my_helper.dart', symbol('registerWith'), null),
        isFalse,
      );
    });

    test('a qualified name matches a member of that container only', () {
      final rule = EntryPoint.parse('MyPlugin.registerWith');

      expect(
        rule.matches(
          'lib/a.dart',
          symbol('registerWith', kind: .method),
          'MyPlugin',
        ),
        isTrue,
      );
      expect(
        rule.matches(
          'lib/a.dart',
          symbol('registerWith', kind: .method),
          'Other',
        ),
        isFalse,
      );
      expect(rule.matches('lib/a.dart', symbol('registerWith'), null), isFalse);
    });

    test('a parsed rule accepts any kind and signature', () {
      final rule = EntryPoint.parse('handler');

      expect(rule.kind, isNull);
      expect(
        rule.matches('x.dart', symbol('handler', kind: .variable), null),
        isTrue,
      );
      expect(
        rule.matches(
          'x.dart',
          symbol('handler', detail: '(int a, String b)'),
          null,
        ),
        isTrue,
      );
    });

    test('trims whitespace and prints back as the spec', () {
      expect('${EntryPoint.parse(' test/**:setUpAll ')}', 'test/**:setUpAll');
      expect('${EntryPoint.parse('bootstrap')}', 'bootstrap');
    });

    test('rejects an empty name', () {
      for (final spec in ['', '   ', 'lib/**:', 'lib/**:  ']) {
        expect(
          () => EntryPoint.parse(spec),
          throwsA(isFormatException(contains('names no declaration'))),
          reason: "for '$spec'",
        );
      }
    });

    test('rejects a name that is not an identifier', () {
      for (final name in ['a-b', '1abc', 'a.b.c', 'a b', 'A.']) {
        expect(
          () => EntryPoint.parse(name),
          throwsA(isFormatException(contains('not a declaration name'))),
          reason: "for '$name'",
        );
      }
    });

    test('rejects an empty glob rather than silently matching nothing', () {
      expect(
        () => EntryPoint.parse(':main'),
        throwsA(isFormatException(contains('empty file glob'))),
      );
    });

    test('rejects an invalid glob, naming it', () {
      expect(
        () => EntryPoint.parse('lib/[:x'),
        throwsA(isFormatException(contains("'lib/[' is not a valid glob"))),
      );
    });
  });

  group('built-in conventions', () {
    final rules = EntryPoints(const []);

    test('main is an entry point in every file, as a function only', () {
      expect(rules.match('bin/app.dart', symbol('main'), null)?.name, 'main');
      expect(rules.match('test/a_test.dart', symbol('main'), null), isNotNull);
      // A `main` method or field is an ordinary declaration.
      expect(
        rules.match('lib/a.dart', symbol('main', kind: .method), 'Runner'),
        isNull,
      );
      expect(
        rules.match('lib/a.dart', symbol('main', kind: .variable), null),
        isNull,
      );
    });

    group('testExecutable', () {
      const detail = '(FutureOr<void> Function() testMain)';

      test('in a flutter_test_config.dart with the bootstrap signature', () {
        for (final path in [
          'test/flutter_test_config.dart',
          'flutter_test_config.dart',
          'integration_test/nested/flutter_test_config.dart',
        ]) {
          final rule = rules.match(
            path,
            symbol('testExecutable', detail: detail),
            null,
          );
          expect(rule?.name, 'testExecutable', reason: 'for $path');
          expect(rule?.reason, contains('flutter test'));
        }
      });

      test('is not exempt in any other file', () {
        expect(
          rules.match(
            'test/test_config.dart',
            symbol('testExecutable', detail: detail),
            null,
          ),
          isNull,
        );
        expect(
          rules.match(
            'test/my_flutter_test_config.dart',
            symbol('testExecutable', detail: detail),
            null,
          ),
          isNull,
        );
      });

      test('is not exempt with a shape the bootstrap could not call', () {
        for (final wrong in [
          '()',
          '(int retries)',
          '(Function() a, int b)',
          null,
        ]) {
          expect(
            rules.match(
              'test/flutter_test_config.dart',
              symbol('testExecutable', detail: wrong),
              null,
            ),
            isNull,
            reason: 'for $wrong',
          );
        }
      });

      test('is not exempt as a member', () {
        expect(
          rules.match(
            'test/flutter_test_config.dart',
            symbol('testExecutable', kind: .method, detail: detail),
            'Config',
          ),
          isNull,
        );
      });
    });
  });

  test('a project rule is consulted after the built-in ones', () {
    final rules = EntryPoints([EntryPoint.parse('tool/**:main')]);

    expect(
      rules.match('tool/gen.dart', symbol('main'), null)?.reason,
      'the program entry point',
    );
    expect(rules.match('lib/a.dart', symbol('serve'), null), isNull);
    expect(
      EntryPoints([
        EntryPoint.parse('serve'),
      ]).match('lib/a.dart', symbol('serve'), null)?.reason,
      contains('this project'),
    );
  });
}

/// A [FormatException] whose message matches [message].
Matcher isFormatException(Matcher message) =>
    isA<FormatException>().having((e) => e.message, 'message', message);
