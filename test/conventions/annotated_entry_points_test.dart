/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:test/test.dart';

import '../support/declarations.dart';

/// The rules that select a declaration by the class of an annotation on it.
void main() {
  group('EntryPoint.annotatedWith', () {
    /// An annotation that creates an object of [type], from [package], whose
    /// [supertypes] come from the same package.
    ResolvedAnnotation annotation(
      String type, {
      List<String> supertypes = const [],
      String? package,
    }) => .new(.new(type, package), {
      for (final supertype in supertypes) .new(supertype, package),
    });

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
      final rule = EntryPoint.annotatedWith('Story', reason: 'shown');

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

    test('with no package, counts a class from any package', () {
      final rule = EntryPoint.annotatedWith('Story', reason: 'shown');

      expect(
        matchesCard(rule, [annotation('Story', package: 'stories')]),
        isTrue,
      );
    });

    test('a package counts only the class from that package', () {
      final rule = EntryPoint.annotatedWith(
        'Story',
        package: 'stories',
        reason: 'shown',
      );

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
      final rule = EntryPoint.annotatedWith(
        'Story',
        reason: 'shown',
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
      final rule = EntryPoint.annotatedWith(
        'Story',
        package: 'stories',
        reason: 'shown',
      ).within('app');

      expect(rule, isA<AnnotatedEntryPoint>());
      rule as AnnotatedEntryPoint;
      expect(
        (rule.annotation, rule.package, rule.reason),
        ('Story', 'stories', 'shown'),
      );
      expect(rule.files, ['app/**']);
    });

    test('prints as the annotation, its package and its files', () {
      expect(
        '${EntryPoint.annotatedWith('Story', reason: 'shown', files: ['lib/**'])}',
        'declarations annotated with `@Story` or a subtype of it in lib/**',
      );
      expect(
        '${EntryPoint.annotatedWith('Story', package: 'stories', reason: 'shown')}',
        'declarations annotated with `@Story` from `package:stories` or a subtype of it',
      );
    });
  });
}
