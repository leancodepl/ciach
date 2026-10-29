import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';
import '../support/format_exception.dart';

void main() {
  group('EntryPoint.fromConfig', () {
    test('a bare name matches in any file, whatever the kind', () {
      final rule = EntryPoint.fromConfig('bootstrap');

      expect(rule.files, isEmpty);
      expect(
        rule.matches(declarationAt('lib/a.dart', symbol('bootstrap'), null)),
        isTrue,
      );
      expect(
        rule.matches(declarationAt('bin/b.dart', symbol('bootstrap'), null)),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt(
            'lib/a.dart',
            symbol('bootstrap', kind: .variable),
            null,
          ),
        ),
        isTrue,
      );
      expect(
        rule.matches(declarationAt('lib/a.dart', symbol('bootstrapped'), null)),
        isFalse,
      );
    });

    test('globs narrow the file, any of them matching', () {
      final rule = EntryPoint.fromConfig(
        'registerWith',
        files: ['lib/**_plugin.dart', 'bin/**'],
      );

      expect(
        rule.matches(
          declarationAt('lib/src/my_plugin.dart', symbol('registerWith'), null),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt('bin/tool.dart', symbol('registerWith'), null),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt('lib/src/my_helper.dart', symbol('registerWith'), null),
        ),
        isFalse,
      );
    });

    test('a qualified name matches a member of that container only', () {
      final rule = EntryPoint.fromConfig('MyPlugin.registerWith');
      final member = symbol('registerWith', kind: .method);

      expect(
        rule.matches(declarationAt('lib/a.dart', member, 'MyPlugin')),
        isTrue,
      );
      expect(
        rule.matches(declarationAt('lib/a.dart', member, 'Other')),
        isFalse,
      );
      expect(
        rule.matches(declarationAt('lib/a.dart', symbol('registerWith'), null)),
        isFalse,
      );
    });

    test('a constructor rule uses the name the report prints', () {
      final unnamed = symbol('Parked', kind: .constructor);
      final named = symbol('Parked.make', kind: .constructor);

      expect(
        EntryPoint.fromConfig(
          'Parked.new',
        ).matches(declarationAt('a.dart', unnamed, 'Parked')),
        isTrue,
      );
      expect(
        EntryPoint.fromConfig(
          'Parked.make',
        ).matches(declarationAt('a.dart', named, 'Parked')),
        isTrue,
      );
      expect(
        EntryPoint.fromConfig(
          'Parked.new',
        ).matches(declarationAt('a.dart', named, 'Parked')),
        isFalse,
      );
    });

    test('a type name matches its unnamed constructor, except in an enum', () {
      final rule = EntryPoint.fromConfig('Card');
      final unnamed = symbol('Card', kind: .constructor);
      final named = symbol('Card.blank', kind: .constructor);

      expect(
        rule.matches(declarationAt('lib/a.dart', unnamed, 'Card')),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt('lib/a.dart', unnamed, 'Card', inEnum: true),
        ),
        isFalse,
      );
      expect(rule.matches(declarationAt('lib/a.dart', named, 'Card')), isFalse);
      expect(
        rule.matches(
          declarationAt('lib/a.dart', symbol('Card', kind: .method), 'Card'),
        ),
        isFalse,
      );
    });

    test('Class.Class is rejected with a hint to write Class.new', () {
      expect(
        () => EntryPoint.fromConfig('Parked.Parked'),
        throwsA(formatExceptionWith(contains('`Parked.new`'))),
      );
    });

    test('a bare name never matches a member', () {
      final rule = EntryPoint.fromConfig('registerWith');

      expect(
        rule.matches(
          declarationAt(
            'lib/a.dart',
            symbol('registerWith', kind: .method),
            'P',
          ),
        ),
        isFalse,
      );
    });

    test('prints as the name and its files', () {
      expect('${EntryPoint.fromConfig('bootstrap')}', 'bootstrap');
      expect(
        '${EntryPoint.fromConfig('run', files: ['a/**', 'b/**'])}',
        'run in a/** or b/**',
      );
    });

    test('rejects type parameters in a name, with a hint', () {
      expect(
        () => EntryPoint.fromConfig('Box<T>.convert'),
        throwsA(formatExceptionWith(contains('type parameters are not part'))),
      );
    });

    test('rejects a name that is not an identifier', () {
      for (final name in ['', 'a-b', '1abc', 'a.b.c', 'a b', 'A.']) {
        expect(
          () => EntryPoint.fromConfig(name),
          throwsA(formatExceptionWith(contains('not a declaration name'))),
          reason: "for '$name'",
        );
      }
    });

    test('rejects an invalid glob with the glob as the error source', () {
      expect(
        () => EntryPoint.fromConfig('x', files: ['lib/[']),
        throwsA(
          isA<FormatException>().having((e) => e.source, 'source', 'lib/['),
        ),
      );
    });
  });

  group('built-in conventions', () {
    final rules = EntryPoints(const []);

    /// A class annotated with `@[annotation]`.
    ResolvedDeclaration annotatedClass(String annotation) => .new(
      relativePath: 'lib/a.dart',
      symbol: symbol('Counter', kind: .class$),
      leadingMetadata: [
        SemanticToken(
          line: 0,
          character: 1,
          length: annotation.length,
          type: 'class',
          modifiers: const {'annotation'},
          text: annotation,
        ),
      ],
    );

    test('`@JSExport` keeps the class and its public members', () {
      final counter = annotatedClass('JSExport');

      expect(rules.match(counter)?.reason, contains('`@JSExport`'));
      expect(rules.keptMembersOf(counter).map((members) => members.selection), [
        MemberSelection.publicMembers,
      ]);
    });

    test('`@reflectiveTest` keeps the test methods but not the class', () {
      final test = annotatedClass('reflectiveTest');

      expect(rules.match(test), isNull);
      expect(rules.keptMembersOf(test).map((members) => members.selection), [
        MemberSelection.reflectiveTestMethods,
      ]);
    });

    test('main is an entry point in every file, but not as a member', () {
      expect(
        rules.match(declarationAt('bin/app.dart', symbol('main'), null))?.label,
        'main',
      );
      expect(
        rules.match(declarationAt('test/a_test.dart', symbol('main'), null)),
        isNotNull,
      );
      expect(
        rules.match(
          declarationAt('lib/a.dart', symbol('main', kind: .method), 'Runner'),
        ),
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
          final rule = rules.match(
            declarationAt(path, symbol('testExecutable'), null),
          );
          expect(rule?.label, 'testExecutable', reason: 'for $path');
          expect(rule?.reason, contains('flutter test'));
        }
      });

      test('whatever its shape — the bootstrap calls it regardless', () {
        expect(
          rules.match(
            declarationAt(
              'test/flutter_test_config.dart',
              symbol('testExecutable', kind: .variable),
              null,
            ),
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
            rules.match(declarationAt(path, symbol('testExecutable'), null)),
            isNull,
            reason: 'for $path',
          );
        }
      });

      test('is not exempt as a member', () {
        expect(
          rules.match(
            declarationAt(
              'test/flutter_test_config.dart',
              symbol('testExecutable', kind: .method),
              'Config',
            ),
          ),
          isNull,
        );
      });
    });
  });

  test('a project rule is consulted after the built-in ones', () {
    final rules = EntryPoints([
      .fromConfig('main', files: ['tool/**']),
    ]);

    expect(
      rules.match(declarationAt('tool/gen.dart', symbol('main'), null))?.reason,
      'the program entry point',
    );
    expect(
      rules.match(declarationAt('lib/a.dart', symbol('serve'), null)),
      isNull,
    );
    expect(
      EntryPoints([
        .fromConfig('serve'),
      ]).match(declarationAt('lib/a.dart', symbol('serve'), null))?.reason,
      contains('entry-points'),
    );
  });
}
