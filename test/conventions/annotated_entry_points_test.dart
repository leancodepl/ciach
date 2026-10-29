/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:pro_lsp/pro_lsp.dart';
import 'package:test/test.dart';

import '../support/format_exception.dart';

/// The rules that select a declaration by the class of an annotation or by a
/// supertype, and the members that they keep.
void main() {
  /// A symbol as the server reports it; the shape is irrelevant to the rules.
  DocumentSymbol symbol(String name, {SymbolKind kind = .function}) {
    const range = Range(
      start: .new(line: 0, character: 0),
      end: .new(line: 0, character: 0),
    );
    return .new(name: name, kind: kind, range: range, selectionRange: range);
  }

  /// [symbol] in the file at [path], inside [container].
  ResolvedDeclaration at(
    String path,
    DocumentSymbol symbol,
    String? container, {
    bool inEnum = false,
    List<ResolvedAnnotation> annotations = const [],
  }) => .new(
    relativePath: path,
    symbol: symbol,
    container: container,
    inEnum: inEnum,
    annotations: annotations,
  );

  group('EntryPoint.annotationFromConfig', () {
    /// An annotation that creates an object of [type], from [package], whose
    /// [supertypes] come from the same package.
    ResolvedAnnotation annotation(
      String type, {
      List<String> supertypes = const [],
      String? package,
      bool readsConstant = false,
    }) => .new(.new(type, package), {
      for (final supertype in supertypes) .new(supertype, package),
    }, readsConstant: readsConstant);

    /// Whether [rule] matches a function annotated with [annotations].
    bool matchesCard(EntryPoint rule, List<ResolvedAnnotation> annotations) =>
        rule.matches(
          at('lib/a.dart', symbol('card'), null, annotations: annotations),
        );

    test('matches a declaration annotated with the class or a subtype', () {
      final rule = EntryPoint.annotationFromConfig('Story');

      expect(matchesCard(rule, [annotation('Story')]), isTrue);
      expect(
        matchesCard(rule, [
          annotation('DarkStory', supertypes: ['Story']),
        ]),
        isTrue,
      );
      expect(
        rule.matches(
          at(
            'lib/a.dart',
            symbol('card', kind: .method),
            'Gallery',
            annotations: [annotation('Story')],
          ),
        ),
        isTrue,
      );
      expect(matchesCard(rule, [annotation('Deprecated')]), isFalse);
      // A declaration named like the class is not annotated with it.
      expect(rule.matches(at('lib/a.dart', symbol('Story'), null)), isFalse);
    });

    test('by default counts a constant and a class from any package', () {
      final rule = EntryPoint.annotationFromConfig('Story');

      expect(
        matchesCard(rule, [annotation('Story', readsConstant: true)]),
        isTrue,
      );
      expect(
        matchesCard(rule, [annotation('Story', package: 'stories')]),
        isTrue,
      );
    });

    test('`subtypes: false` counts only the class itself', () {
      final rule = EntryPoint.annotationFromConfig('Story', subtypes: false);

      expect(matchesCard(rule, [annotation('Story')]), isTrue);
      expect(
        matchesCard(rule, [
          annotation('DarkStory', supertypes: ['Story']),
        ]),
        isFalse,
      );
    });

    test('`constants: false` counts only a constructor call', () {
      final rule = EntryPoint.annotationFromConfig('Story', constants: false);

      expect(matchesCard(rule, [annotation('Story')]), isTrue);
      expect(
        matchesCard(rule, [annotation('Story', readsConstant: true)]),
        isFalse,
      );
    });

    test('a package counts only the class from that package', () {
      final rule = EntryPoint.annotationFromConfig('Story', package: 'stories');

      expect(
        matchesCard(rule, [annotation('Story', package: 'stories')]),
        isTrue,
      );
      expect(
        matchesCard(rule, [
          annotation('DarkStory', supertypes: ['Story'], package: 'stories'),
        ]),
        isTrue,
      );
      expect(matchesCard(rule, [annotation('Story', package: 'app')]), isFalse);
      expect(matchesCard(rule, [annotation('Story')]), isFalse);
    });

    test('globs narrow the file', () {
      final rule = EntryPoint.annotationFromConfig(
        'Story',
        files: ['lib/stories/**'],
      );
      final story = [annotation('Story')];

      expect(
        rule.matches(
          at('lib/stories/card.dart', symbol('card'), null, annotations: story),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          at('lib/card.dart', symbol('card'), null, annotations: story),
        ),
        isFalse,
      );
    });

    test('limited to a package, it keeps what it selects', () {
      final rule = EntryPoint.annotationFromConfig(
        'Story',
        package: 'stories',
        subtypes: false,
        constants: false,
      ).within('app');

      expect(rule, isA<AnnotatedEntryPoint>());
      rule as AnnotatedEntryPoint;
      expect(
        (rule.annotation, rule.package, rule.subtypes, rule.constants),
        ('Story', 'stories', false, false),
      );
      expect(rule.files, ['app/**']);
    });

    test('prints as the annotation, what counts and its files', () {
      expect(
        '${EntryPoint.annotationFromConfig('Story', files: ['lib/**'])}',
        'declarations annotated with `@Story` or a subtype of it in lib/**',
      );
      expect(
        '${EntryPoint.annotationFromConfig('Story', package: 'stories', subtypes: false, constants: false)}',
        'declarations annotated with `@Story` from `package:stories` by a constructor call',
      );
    });

    test('rejects an `@` before the class name, with a hint', () {
      expect(
        () => EntryPoint.annotationFromConfig('@Story'),
        throwsA(formatExceptionWith(contains('without `@`, such as `Story`'))),
      );
    });

    test('rejects an annotation that is not a class name', () {
      for (final annotation in ['', 'a-b', 'Story.dark', 'Story()']) {
        expect(
          () => EntryPoint.annotationFromConfig(annotation),
          throwsA(formatExceptionWith(contains('not a class name'))),
          reason: "for '$annotation'",
        );
      }
    });

    test('rejects a package that is not a package name', () {
      for (final package in ['', 'package:stories', 'Stories', 'a-b']) {
        expect(
          () => EntryPoint.annotationFromConfig('Story', package: package),
          throwsA(formatExceptionWith(contains('not a package name'))),
          reason: "for '$package'",
        );
      }
    });
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
      expect(rules.keepingMembersOf(endpoint), [rule]);
      expect(rule.members?.includes(symbol('hello', kind: .method)), isTrue);
      expect(rule.members?.includes(symbol('_helper', kind: .method)), isFalse);
      expect(rule.members?.includes(symbol('name', kind: .field)), isFalse);
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
