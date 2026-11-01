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

    /// A class annotated with `@[annotation]`, which [package] declares.
    ResolvedDeclaration annotatedClass(
      String annotation, {
      required String package,
    }) => .new(
      relativePath: 'lib/a.dart',
      symbol: symbol('Counter', kind: .class$),
      annotationPackages: {const .new(line: 0, character: 1): package},
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
      final counter = annotatedClass('JSExport', package: 'dart:js_interop');

      expect(rules.match(counter)?.reason, contains('`@JSExport`'));
      expect(rules.keptMembersOf(counter).map((members) => members.selection), [
        MemberSelection.publicMembers,
      ]);
    });

    test(
      '`@JSExport` from `dart:_js_annotations` or `package:js` keeps the class',
      () {
        for (final package in ['dart:_js_annotations', 'js']) {
          expect(
            rules.match(annotatedClass('JSExport', package: package)),
            isNotNull,
            reason: 'for $package',
          );
        }
      },
    );

    test('a `JSExport` from another package keeps nothing', () {
      final counter = annotatedClass('JSExport', package: 'app');

      expect(rules.match(counter), isNull);
      expect(rules.keptMembersOf(counter), isEmpty);
    });

    test('`@reflectiveTest` keeps the test methods but not the class', () {
      final test = annotatedClass(
        'reflectiveTest',
        package: 'test_reflective_loader',
      );

      expect(rules.match(test), isNull);
      expect(rules.keptMembersOf(test).map((members) => members.selection), [
        MemberSelection.reflectiveTestMethods,
      ]);
    });

    test('a `reflectiveTest` from another package keeps no methods', () {
      expect(
        rules.keptMembersOf(annotatedClass('reflectiveTest', package: 'app')),
        isEmpty,
      );
    });

    test('an annotation whose package is unknown keeps nothing', () {
      final counter = ResolvedDeclaration(
        relativePath: 'lib/a.dart',
        symbol: symbol('Counter', kind: .class$),
        leadingMetadata: annotatedClass(
          'JSExport',
          package: 'dart:js_interop',
        ).leadingMetadata,
      );

      expect(rules.match(counter), isNull);
      expect(rules.keptMembersOf(counter), isEmpty);
    });

    test(
      'the built-in rules name `JSExport`, `pragma` and `reflectiveTest`',
      () {
        expect(rules.annotationNamesIn('lib/a.dart'), {
          'JSExport',
          'pragma',
          'reflectiveTest',
        });
      },
    );

    /// A token of [type] with [text], such as `(` or `'vm:entry-point'`.
    SemanticToken token(
      String type,
      String text, {
      Set<String> modifiers = const {},
    }) => .new(
      line: 0,
      character: 0,
      length: text.length,
      type: type,
      modifiers: modifiers,
      text: text,
    );

    /// The tokens of `@[name]([arguments])`, with [prefix] before [name].
    List<SemanticToken> annotation(
      String name,
      List<String> arguments, {
      String? prefix,
    }) => [
      token('annotation', '@'),
      if (prefix != null) ...[
        token('variable', prefix, modifiers: const {'importPrefix'}),
        token('annotation', '.'),
      ],
      token('class', name, modifiers: const {'annotation'}),
      token('annotation', '('),
      for (final argument in arguments) token('string', argument),
      token('annotation', ')'),
    ];

    /// A function whose annotation has the tokens [leadingMetadata] and is
    /// declared in [package].
    ResolvedDeclaration annotatedFunction(
      List<SemanticToken> leadingMetadata, {
      String package = 'dart:core',
    }) => .new(
      relativePath: 'lib/a.dart',
      symbol: symbol('callback'),
      leadingMetadata: leadingMetadata,
      annotationPackages: {const .new(line: 0, character: 0): package},
    );

    test(
      "`@pragma('vm:entry-point')` keeps the declaration, with an import prefix, any quotes or a second argument",
      () {
        for (final leadingMetadata in [
          annotation('pragma', ["'vm:entry-point'"]),
          annotation('pragma', ['"vm:entry-point"'], prefix: 'core'),
          annotation('pragma', ["r'vm:entry-point'", "'call'"]),
        ]) {
          expect(
            rules.match(annotatedFunction(leadingMetadata))?.reason,
            "marked `@pragma('vm:entry-point')` for native code or reflection",
            reason: 'for ${leadingMetadata.map((t) => t.text).join()}',
          );
        }
      },
    );

    test(
      "another `@pragma` value, `vm:entry-point` as a second argument and `@Deprecated('vm:entry-point')` keep nothing",
      () {
        for (final leadingMetadata in [
          annotation('pragma', ["'vm:prefer-inline'"]),
          annotation('pragma', ["'dart2js:noInline'", "'vm:entry-point'"]),
          annotation('Deprecated', ["'vm:entry-point'"]),
        ]) {
          expect(
            rules.match(annotatedFunction(leadingMetadata)),
            isNull,
            reason: 'for ${leadingMetadata.map((t) => t.text).join()}',
          );
        }
      },
    );

    test('a `pragma` from another package keeps nothing', () {
      expect(
        rules.match(
          annotatedFunction(
            annotation('pragma', ["'vm:entry-point'"]),
            package: 'app',
          ),
        ),
        isNull,
      );
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

  group('EntryPoint.publicMethodsOfSubclasses', () {
    final rule = EntryPoint.publicMethodsOfSubclasses(
      'Endpoint',
      package: 'serverpod',
      reason: 'called by the Serverpod dispatcher',
    );
    final rules = EntryPoints([rule]);
    final endpoint = ResolvedDeclaration(
      relativePath: 'lib/greeting.dart',
      symbol: symbol('GreetingEndpoint', kind: .class$),
      supertypes: {
        const .new('Endpoint', 'serverpod'),
        const .new('Object', null),
      },
    );

    test('keeps a class with the supertype from that package', () {
      expect(rules.match(endpoint), rule);
      expect(
        rules.match(
          .new(
            relativePath: 'lib/greeting.dart',
            symbol: symbol('LocalEndpoint', kind: .class$),
            supertypes: {const .new('Endpoint', 'app')},
          ),
        ),
        isNull,
      );
    });

    test('keeps the public methods of such a class', () {
      final members = rules.keptMembersOf(endpoint).single;
      expect(members, same(rule.members));
      expect(
        members.selection.includes(symbol('hello', kind: .method)),
        isTrue,
      );
      expect(
        members.selection.includes(symbol('_helper', kind: .method)),
        isFalse,
      );
      expect(members.selection.includes(symbol('name', kind: .field)), isFalse);
    });
  });

  group('MemberSelection', () {
    test('`publicMembers` takes every public member but constructors', () {
      expect(
        [
          symbol('value', kind: .field),
          symbol('increment', kind: .method),
          symbol('_hidden', kind: .method),
          symbol('Counter', kind: .constructor),
        ].where(MemberSelection.publicMembers.includes).map((s) => s.name),
        ['value', 'increment'],
      );
    });

    test('`reflectiveTestMethods` takes the methods that run as tests', () {
      expect(
        [
              symbol('test_parses', kind: .method),
              symbol('setUp', kind: .method),
              symbol('helper', kind: .method),
              symbol('test_field', kind: .field),
            ]
            .where(MemberSelection.reflectiveTestMethods.includes)
            .map((s) => s.name),
        ['test_parses', 'setUp'],
      );
    });
  });
}
