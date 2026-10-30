/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';
import '../support/format_exception.dart';

/// The rules that select a declaration by the class of an annotation on it.
void main() {
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
          declarationAt(
            'lib/a.dart',
            symbol('card'),
            null,
            annotations: annotations,
          ),
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
          declarationAt(
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
      expect(
        rule.matches(declarationAt('lib/a.dart', symbol('Story'), null)),
        isFalse,
      );
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

    test('a glob limits the rule to the files that it matches', () {
      final rule = EntryPoint.annotationFromConfig(
        'Story',
        files: ['lib/stories/**'],
      );
      final story = [annotation('Story')];

      expect(
        rule.matches(
          declarationAt(
            'lib/stories/card.dart',
            symbol('card'),
            null,
            annotations: story,
          ),
        ),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt(
            'lib/card.dart',
            symbol('card'),
            null,
            annotations: story,
          ),
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
}
