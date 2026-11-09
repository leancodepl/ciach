/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';

/// The rules that select a declaration by the class that an annotation on it
/// creates, or a subtype of that class.
void main() {
  group('EntryPoint.annotationNamed with `subtypes`', () {
    /// The class [type] that an annotation creates, from [package], whose
    /// [supertypes] come from the same package.
    AnnotationClass annotationClass(
      String type, {
      List<String> supertypes = const [],
      String? package = 'stories',
    }) => .new(.new(type, package), {
      for (final supertype in supertypes) .new(supertype, package),
    });

    /// Whether [rule] matches a function annotated with [annotationClasses].
    bool matchesCard(
      EntryPoint rule,
      List<AnnotationClass> annotationClasses,
    ) => rule.matches(
      declarationAt(
        'lib/a.dart',
        declared('card'),
        null,
        annotationClasses: annotationClasses,
      ),
    );

    test('matches a declaration annotated with the class or a subtype', () {
      final rule = EntryPoint.annotationNamed(
        'Story',
        packages: const {'stories'},
        subtypes: true,
        reason: 'shown',
      );

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
            declared('card', kind: .method),
            'Gallery',
            annotationClasses: [annotationClass('Story')],
          ),
        ),
        isTrue,
      );
      expect(matchesCard(rule, [annotationClass('Deprecated')]), isFalse);
      // A declaration named like the class is not annotated with it.
      expect(
        rule.matches(declarationAt('lib/a.dart', declared('Story'), null)),
        isFalse,
      );
    });

    test('a package counts only the class from that package', () {
      final rule = EntryPoint.annotationNamed(
        'Story',
        packages: const {'stories'},
        subtypes: true,
        reason: 'shown',
      );

      expect(matchesCard(rule, [annotationClass('Story')]), isTrue);
      expect(
        matchesCard(rule, [
          annotationClass('DarkStory', supertypes: ['Story']),
        ]),
        isTrue,
      );
      expect(
        matchesCard(rule, [annotationClass('Story', package: 'app')]),
        isFalse,
      );
      // A class that no package declares, as in the SDK.
      expect(
        matchesCard(rule, [annotationClass('Story', package: null)]),
        isFalse,
      );
    });

    test('a glob limits the rule to the files that it matches', () {
      final rule = EntryPoint.annotationNamed(
        'Story',
        packages: const {'stories'},
        subtypes: true,
        reason: 'shown',
        files: ['lib/stories/**'],
      );
      final story = [annotationClass('Story')];

      expect(
        rule.matches(
          declarationAt(
            'lib/stories/card.dart',
            declared('card'),
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
            declared('card'),
            null,
            annotationClasses: story,
          ),
        ),
        isFalse,
      );
    });

    test('limited to a package, it keeps what it selects', () {
      final rule = EntryPoint.annotationNamed(
        'Story',
        packages: const {'stories'},
        subtypes: true,
        reason: 'shown',
      ).within('app');

      expect(rule, isA<AnnotationNamedEntryPoint>());
      rule as AnnotationNamedEntryPoint;
      expect(
        (rule.annotation, rule.subtypes, rule.reason),
        ('Story', true, 'shown'),
      );
      expect(rule.packages, {'stories'});
      expect(rule.files, ['app/**']);
    });

    test('without `subtypes`, a subclass of the annotation keeps nothing', () {
      final rule = EntryPoint.annotationNamed(
        'Story',
        packages: const {'stories'},
        reason: 'shown',
      );

      expect(
        matchesCard(rule, [
          annotationClass('DarkStory', supertypes: ['Story']),
        ]),
        isFalse,
      );
    });

    test('prints as the annotation, its package and its files', () {
      expect(
        '${EntryPoint.annotationNamed('Story', packages: {'stories', 'dart:core'}, subtypes: true, reason: 'shown', files: ['lib/**'])}',
        'declarations annotated with `@Story` from `package:stories` or `dart:core` or a subtype of it in lib/**',
      );
    });
  });
}
