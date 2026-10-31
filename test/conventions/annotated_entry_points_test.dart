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
    /// The class [type] that an annotation creates, from [package], whose
    /// [supertypes] come from the same package.
    AnnotationClass annotationClass(
      String type, {
      List<String> supertypes = const [],
      String? package,
      bool readsConstant = false,
    }) => .new(.new(type, package), {
      for (final supertype in supertypes) .new(supertype, package),
    }, readsConstant: readsConstant);

    /// Whether [rule] matches a function annotated with [annotationClasses].
    bool matchesCard(
      EntryPoint rule,
      List<AnnotationClass> annotationClasses,
    ) => rule.matches(
      declarationAt(
        'lib/a.dart',
        symbol('card'),
        null,
        annotationClasses: annotationClasses,
      ),
    );

    test('matches a declaration annotated with the class or a subtype', () {
      final rule = EntryPoint.annotationFromConfig('Story');

      expect(matchesCard(rule, [annotationClass('Story')]), isTrue);
      expect(
        matchesCard(rule, [
          annotationClass('DarkStory', supertypes: ['Story']),
        ]),
        isTrue,
      );
      expect(
        rule.matches(
          declarationAt(
            'lib/a.dart',
            symbol('card', kind: .method),
            'Gallery',
            annotationClasses: [annotationClass('Story')],
          ),
        ),
        isTrue,
      );
      expect(matchesCard(rule, [annotationClass('Deprecated')]), isFalse);
      // A declaration named like the class is not annotated with it.
      expect(
        rule.matches(declarationAt('lib/a.dart', symbol('Story'), null)),
        isFalse,
      );
    });

    test('by default counts a constant and a class from any package', () {
      final rule = EntryPoint.annotationFromConfig('Story');

      expect(
        matchesCard(rule, [annotationClass('Story', readsConstant: true)]),
        isTrue,
      );
      expect(
        matchesCard(rule, [annotationClass('Story', package: 'stories')]),
        isTrue,
      );
    });

    test('`subtypes: false` counts only the class itself', () {
      final rule = EntryPoint.annotationFromConfig('Story', subtypes: false);

      expect(matchesCard(rule, [annotationClass('Story')]), isTrue);
      expect(
        matchesCard(rule, [
          annotationClass('DarkStory', supertypes: ['Story']),
        ]),
        isFalse,
      );
    });

    test('`constants: false` counts only a constructor call', () {
      final rule = EntryPoint.annotationFromConfig('Story', constants: false);

      expect(matchesCard(rule, [annotationClass('Story')]), isTrue);
      expect(
        matchesCard(rule, [annotationClass('Story', readsConstant: true)]),
        isFalse,
      );
    });

    test('a package counts only the class from that package', () {
      final rule = EntryPoint.annotationFromConfig('Story', package: 'stories');

      expect(
        matchesCard(rule, [annotationClass('Story', package: 'stories')]),
        isTrue,
      );
      expect(
        matchesCard(rule, [
          annotationClass(
            'DarkStory',
            supertypes: ['Story'],
            package: 'stories',
          ),
        ]),
        isTrue,
      );
      expect(
        matchesCard(rule, [annotationClass('Story', package: 'app')]),
        isFalse,
      );
      expect(matchesCard(rule, [annotationClass('Story')]), isFalse);
    });

    test('a glob limits the rule to the files that it matches', () {
      final rule = EntryPoint.annotationFromConfig(
        'Story',
        files: ['lib/stories/**'],
      );
      final story = [annotationClass('Story')];

      expect(
        rule.matches(
          declarationAt(
            'lib/stories/card.dart',
            symbol('card'),
            null,
            annotationClasses: story,
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
            annotationClasses: story,
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
