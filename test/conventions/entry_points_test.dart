import 'package:ciach/src/conventions/entry_points.dart';
import 'package:pro_lsp/pro_lsp.dart';
import 'package:test/test.dart';

void main() {
  /// A symbol as the server reports it; the shape is irrelevant to the rules.
  DocumentSymbol symbol(String name, {SymbolKind kind = .function}) {
    const range = Range(
      start: .new(line: 0, character: 0),
      end: .new(line: 0, character: 0),
    );
    return .new(name: name, kind: kind, range: range, selectionRange: range);
  }

  group('EntryPoint.fromConfig', () {
    test('a bare name matches in any file, whatever the kind', () {
      final rule = EntryPoint.fromConfig('bootstrap');

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
      final rule = EntryPoint.fromConfig(
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
      final rule = EntryPoint.fromConfig('MyPlugin.registerWith');
      final member = symbol('registerWith', kind: .method);

      expect(rule.matches('lib/a.dart', member, 'MyPlugin'), isTrue);
      expect(rule.matches('lib/a.dart', member, 'Other'), isFalse);
      expect(rule.matches('lib/a.dart', symbol('registerWith'), null), isFalse);
    });

    test('a constructor rule uses the name the report prints', () {
      final unnamed = symbol('Parked', kind: .constructor);
      final named = symbol('Parked.make', kind: .constructor);

      expect(
        EntryPoint.fromConfig(
          'Parked.new',
        ).matches('a.dart', unnamed, 'Parked'),
        isTrue,
      );
      expect(
        EntryPoint.fromConfig('Parked.make').matches('a.dart', named, 'Parked'),
        isTrue,
      );
      expect(
        EntryPoint.fromConfig('Parked.new').matches('a.dart', named, 'Parked'),
        isFalse,
      );
    });

    test('a type name matches its unnamed constructor, except in an enum', () {
      final rule = EntryPoint.fromConfig('Card');
      final unnamed = symbol('Card', kind: .constructor);
      final named = symbol('Card.blank', kind: .constructor);

      expect(rule.matches('lib/a.dart', unnamed, 'Card'), isTrue);
      expect(
        rule.matches('lib/a.dart', unnamed, 'Card', inEnum: true),
        isFalse,
      );
      expect(rule.matches('lib/a.dart', named, 'Card'), isFalse);
      expect(
        rule.matches('lib/a.dart', symbol('Card', kind: .method), 'Card'),
        isFalse,
      );
    });

    test('Class.Class is rejected with a hint to write Class.new', () {
      expect(
        () => EntryPoint.fromConfig('Parked.Parked'),
        throwsA(isFormatException(contains('`Parked.new`'))),
      );
    });

    test('a bare name never matches a member', () {
      final rule = EntryPoint.fromConfig('registerWith');

      expect(
        rule.matches('lib/a.dart', symbol('registerWith', kind: .method), 'P'),
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
        throwsA(isFormatException(contains('type parameters are not part'))),
      );
    });

    test('rejects a name that is not an identifier', () {
      for (final name in ['', 'a-b', '1abc', 'a.b.c', 'a b', 'A.']) {
        expect(
          () => EntryPoint.fromConfig(name),
          throwsA(isFormatException(contains('not a declaration name'))),
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

  group('EntryPoint.annotationFromConfig', () {
    test('matches a declaration annotated with the class or a subclass', () {
      final rule = EntryPoint.annotationFromConfig('Story');

      expect(
        rule.matches(
          'lib/a.dart',
          symbol('card'),
          null,
          annotationTypes: {
            const .new('DarkStory', null),
            const .new('Story', null),
            const .new('Object', null),
          },
        ),
        isTrue,
      );
      expect(
        rule.matches(
          'lib/a.dart',
          symbol('card', kind: .method),
          'Gallery',
          annotationTypes: {
            const .new('Story', null),
            const .new('Object', null),
          },
        ),
        isTrue,
      );
      expect(
        rule.matches(
          'lib/a.dart',
          symbol('card'),
          null,
          annotationTypes: {
            const .new('Deprecated', null),
            const .new('Object', null),
          },
        ),
        isFalse,
      );
      // A declaration named like the class is not annotated with it.
      expect(rule.matches('lib/a.dart', symbol('Story'), null), isFalse);
    });

    test('globs narrow the file', () {
      final rule = EntryPoint.annotationFromConfig(
        'Story',
        files: ['lib/stories/**'],
      );

      expect(
        rule.matches(
          'lib/stories/card.dart',
          symbol('card'),
          null,
          annotationTypes: {const .new('Story', null)},
        ),
        isTrue,
      );
      expect(
        rule.matches(
          'lib/card.dart',
          symbol('card'),
          null,
          annotationTypes: {const .new('Story', null)},
        ),
        isFalse,
      );
    });

    test('limited to a package, it keeps the annotation and its library', () {
      final library = Uri.parse('package:stories/story.dart');
      final rule = EntryPoint.annotatedWith(
        'Story',
        annotationLibrary: library,
        reason: 'shown in the catalog',
      ).within('app');

      expect(rule.annotation, 'Story');
      expect(rule.annotationLibrary, library);
      expect(rule.files, ['app/**']);
    });

    test('matches a class of that name from any library', () {
      expect(
        EntryPoint.annotationFromConfig('Story').matches(
          'lib/a.dart',
          symbol('card'),
          null,
          annotationTypes: {.new('Story', .parse('package:a/story.dart'))},
        ),
        isTrue,
      );
    });

    test('prints as the annotation and its files', () {
      expect(
        '${EntryPoint.annotationFromConfig('Story', files: ['lib/**'])}',
        'declarations annotated with `@Story` or a subclass of it in lib/**',
      );
    });

    test('a rule with a library matches only the class of that library', () {
      final library = Uri.parse('package:stories/story.dart');
      final rule = EntryPoint.annotatedWith(
        'Story',
        annotationLibrary: library,
        reason: 'shown in the catalog',
      );

      bool matches(AnnotationClass type) => rule.matches(
        'lib/a.dart',
        symbol('card'),
        null,
        annotationTypes: {type},
      );
      expect(matches(.new('Story', library)), isTrue);
      expect(matches(.new('Story', .parse('package:app/story.dart'))), isFalse);
      expect(matches(const .new('Story', null)), isFalse);
    });

    test('rejects an `@` before the class name, with a hint', () {
      expect(
        () => EntryPoint.annotationFromConfig('@Story'),
        throwsA(isFormatException(contains('without `@`, such as `Story`'))),
      );
    });

    test('rejects an annotation that is not a class name', () {
      for (final annotation in ['', 'a-b', 'Story.dark', 'Story()']) {
        expect(
          () => EntryPoint.annotationFromConfig(annotation),
          throwsA(isFormatException(contains('not a class name'))),
          reason: "for '$annotation'",
        );
      }
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
      .fromConfig('main', files: ['tool/**']),
    ]);

    expect(
      rules.match('tool/gen.dart', symbol('main'), null)?.reason,
      'the program entry point',
    );
    expect(rules.match('lib/a.dart', symbol('serve'), null), isNull);
    expect(
      EntryPoints([
        .fromConfig('serve'),
      ]).match('lib/a.dart', symbol('serve'), null)?.reason,
      contains('entry-points'),
    );
  });
}

/// A [FormatException] whose message matches [message].
Matcher isFormatException(Matcher message) =>
    isA<FormatException>().having((e) => e.message, 'message', message);
