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
        includeGlobs: const ['lib/scenarios/widget_previews.dart'],
        entryPoints: entryPoints,
      ),
    ).run();
    return result.unused.map((d) => d.qualifiedName).toSet();
  }

  test(
    'keeps the declarations whose annotation is a `Preview` or a `MultiPreview`, or a subtype of either',
    () async {
      expect(await findUnused(), {
        // Used only by `constantPreview`.
        'preview',
        'constantPreview',
        'deprecatedPreview',
        'notAPreview',
        'Gallery.new',
        'Gallery.helper',
        'storyCard',
        'darkStoryCard',
        // Used only by `storyCard` and `darkStoryCard`.
        'Story',
        'DarkStory',
      });
    },
  );

  test(
    'an `annotation` rule keeps the declarations annotated with the class or a subclass of it',
    () async {
      expect(await findUnused(entryPoints: [.annotationFromConfig('Story')]), {
        // Used only by `constantPreview`.
        'preview',
        'constantPreview',
        'deprecatedPreview',
        'notAPreview',
        'Gallery.new',
        'Gallery.helper',
      });
    },
  );
}
