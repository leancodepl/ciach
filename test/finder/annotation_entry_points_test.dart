/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

@Timeout(Duration(minutes: 5))
library;

import 'dart:io';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/finder.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  final fixturePath = p.join(Directory.current.path, 'example');

  Future<Set<String>> findUnused({
    List<EntryPoint> entryPoints = const [],
  }) async {
    final result = await Ciach(
      .new(
        rootPath: fixturePath,
        includeGlobs: const ['lib/scenarios/annotation_entry_points.dart'],
        entryPoints: entryPoints,
      ),
    ).run();
    return result.unused.map((d) => d.qualifiedName).toSet();
  }

  test(
    'reports every declaration that an annotation of the project marks, by default',
    () async {
      expect(await findUnused(), {
        'Story',
        'DarkStory',
        'DarkerStory',
        'StoryLike',
        'story',
        'storyCard',
        'namedStoryCard',
        'darkStoryCard',
        'darkerStoryCard',
        'likeStoryCard',
        'StoryAlias',
        'aliasStoryCard',
        'constantStory',
        'deprecatedStory',
        'notAStory',
        'Gallery',
      });
    },
  );

  test(
    'an `annotation` rule keeps the declarations whose annotation creates an object of the class or of a subtype of it',
    () async {
      expect(await findUnused(entryPoints: [.annotationFromConfig('Story')]), {
        'deprecatedStory',
        'notAStory',
        'Gallery.new',
        'Gallery.helper',
      });
    },
  );

  test(
    'with `subtypes: false`, an `annotation` rule keeps only the declarations annotated with the class itself',
    () async {
      expect(
        await findUnused(
          entryPoints: [.annotationFromConfig('Story', subtypes: false)],
        ),
        {
          'DarkStory',
          'DarkerStory',
          'StoryLike',
          'darkStoryCard',
          'darkerStoryCard',
          'likeStoryCard',
          'StoryAlias',
          'aliasStoryCard',
          'deprecatedStory',
          'notAStory',
          'Gallery.new',
          'Gallery.helper',
        },
      );
    },
  );

  test(
    'with `constants: false`, an `annotation` rule keeps only the declarations whose annotation calls a constructor',
    () async {
      expect(
        await findUnused(
          entryPoints: [.annotationFromConfig('Story', constants: false)],
        ),
        {
          // Used only by `constantStory`.
          'story',
          'constantStory',
          'deprecatedStory',
          'notAStory',
          'Gallery.new',
          'Gallery.helper',
        },
      );
    },
  );
}
