import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';
import '../support/format_exception.dart';

void main() {
  group('EntryPoint.fromConfig', () {
    test('a bare name matches in any file, whatever the kind', () {
      final rule = EntryPoint.fromConfig('bootstrap');

      expect(rule.files, isEmpty);
      expect(
        rule.matches(declarationAt('lib/a.dart', declared('bootstrap'), null)),
        isTrue,
      );
      expect(
        rule.matches(declarationAt('bin/b.dart', declared('bootstrap'), null)),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt(
            'lib/a.dart',
            declared('bootstrap', kind: .topLevelVariable),
            null,
          ),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt('lib/a.dart', declared('bootstrapped'), null),
        ),
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
          declarationAt(
            'lib/src/my_plugin.dart',
            declared('registerWith'),
            null,
          ),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt('bin/tool.dart', declared('registerWith'), null),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt(
            'lib/src/my_helper.dart',
            declared('registerWith'),
            null,
          ),
        ),
        isFalse,
      );
    });

    test('a qualified name matches a member of that container only', () {
      final rule = EntryPoint.fromConfig('MyPlugin.registerWith');
      final member = declared('registerWith', kind: .method);

      expect(
        rule.matches(declarationAt('lib/a.dart', member, 'MyPlugin')),
        isTrue,
      );
      expect(
        rule.matches(declarationAt('lib/a.dart', member, 'Other')),
        isFalse,
      );
      expect(
        rule.matches(
          declarationAt('lib/a.dart', declared('registerWith'), null),
        ),
        isFalse,
      );
    });

    test('a constructor rule uses the name the report prints', () {
      final unnamed = declared('Parked', kind: .constructor);
      final named = declared('Parked.make', kind: .constructor);

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
      final unnamed = declared('Card', kind: .constructor);
      final named = declared('Card.blank', kind: .constructor);

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
          declarationAt('lib/a.dart', declared('Card', kind: .method), 'Card'),
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
            declared('registerWith', kind: .method),
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
      required String? package,
    }) => .new(
      relativePath: 'lib/a.dart',
      outline: declared('Counter', kind: .class$),
      annotations: [.new(annotation, package: package)],
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
      final counter = annotatedClass('JSExport', package: null);

      expect(rules.match(counter), isNull);
      expect(rules.keptMembersOf(counter), isEmpty);
    });

    /// A function annotated with `@[annotation]`, which [package] declares,
    /// whose first argument is the string [argument].
    ResolvedDeclaration annotatedFunction(
      String annotation, {
      String? argument,
      String package = 'dart:core',
    }) => .new(
      relativePath: 'lib/a.dart',
      outline: declared('callback'),
      annotations: [.new(annotation, package: package, argument: argument)],
    );

    test("`@pragma('vm:entry-point')` keeps the declaration", () {
      expect(
        rules
            .match(annotatedFunction('pragma', argument: 'vm:entry-point'))
            ?.reason,
        "marked `@pragma('vm:entry-point')` for native code or reflection",
      );
    });

    test(
      "another `@pragma` value, a `@pragma` without a string and `@Deprecated('vm:entry-point')` keep nothing",
      () {
        for (final declaration in [
          annotatedFunction('pragma', argument: 'vm:prefer-inline'),
          annotatedFunction('pragma'),
          annotatedFunction('Deprecated', argument: 'vm:entry-point'),
        ]) {
          expect(
            rules.match(declaration),
            isNull,
            reason: 'for ${declaration.annotations.single}',
          );
        }
      },
    );

    test('a `pragma` from another package keeps nothing', () {
      expect(
        rules.match(
          annotatedFunction(
            'pragma',
            argument: 'vm:entry-point',
            package: 'app',
          ),
        ),
        isNull,
      );
    });

    test('main is an entry point in every file, but not as a member', () {
      expect(
        rules
            .match(declarationAt('bin/app.dart', declared('main'), null))
            ?.label,
        'main',
      );
      expect(
        rules.match(declarationAt('test/a_test.dart', declared('main'), null)),
        isNotNull,
      );
      expect(
        rules.match(
          declarationAt(
            'lib/a.dart',
            declared('main', kind: .method),
            'Runner',
          ),
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
            declarationAt(path, declared('testExecutable'), null),
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
              declared('testExecutable', kind: .topLevelVariable),
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
            rules.match(declarationAt(path, declared('testExecutable'), null)),
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
              declared('testExecutable', kind: .method),
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
      rules
          .match(declarationAt('tool/gen.dart', declared('main'), null))
          ?.reason,
      'the program entry point',
    );
    expect(
      rules.match(declarationAt('lib/a.dart', declared('serve'), null)),
      isNull,
    );
    expect(
      EntryPoints([
        .fromConfig('serve'),
      ]).match(declarationAt('lib/a.dart', declared('serve'), null))?.reason,
      contains('entry-points'),
    );
  });

  group('EntryPoint.publicMethodsOfSubtypes', () {
    final rule = EntryPoint.publicMethodsOfSubtypes(
      'Endpoint',
      package: 'serverpod',
      reason: 'called by the Serverpod dispatcher',
    );
    final rules = EntryPoints([rule]);
    final endpoint = ResolvedDeclaration(
      relativePath: 'lib/greeting.dart',
      outline: declared('GreetingEndpoint', kind: .class$),
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
            outline: declared('LocalEndpoint', kind: .class$),
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
        members.selection.includes(declared('hello', kind: .method)),
        isTrue,
      );
      expect(
        members.selection.includes(declared('_helper', kind: .method)),
        isFalse,
      );
      expect(
        members.selection.includes(declared('name', kind: .field)),
        isFalse,
      );
    });
  });

  group('MemberSelection', () {
    test('`publicMembers` takes every public member but constructors', () {
      expect(
        [
              declared('value', kind: .field),
              declared('increment', kind: .method),
              declared('_hidden', kind: .method),
              declared('Counter', kind: .constructor),
            ]
            .where(MemberSelection.publicMembers.includes)
            .map((member) => member.element.name),
        ['value', 'increment'],
      );
    });

    test('`reflectiveTestMethods` takes the methods that run as tests', () {
      expect(
        [
              declared('test_parses', kind: .method),
              declared('setUp', kind: .method),
              declared('helper', kind: .method),
              declared('test_field', kind: .field),
            ]
            .where(MemberSelection.reflectiveTestMethods.includes)
            .map((member) => member.element.name),
        ['test_parses', 'setUp'],
      );
    });
  });
}
