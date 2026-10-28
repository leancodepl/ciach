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

import '../support/package_config.dart';

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
        'constantStory',
        'deprecatedStory',
        'notAStory',
        'Gallery',
        // A `Preview` from a library other than Flutter's.
        'Preview',
        'previewWithoutFlutter',
      });
    },
  );

  test(
    'an `annotation` rule keeps the declarations whose annotation calls a constructor of the class or of a subtype of it',
    () async {
      expect(await findUnused(entryPoints: [.annotationFromConfig('Story')]), {
        // Used only by `constantStory`.
        'story',
        'constantStory',
        'deprecatedStory',
        'notAStory',
        'Gallery.new',
        'Gallery.helper',
        'Preview',
        'previewWithoutFlutter',
      });
    },
  );

  test(
    'keeps the declarations whose annotation is a `Preview` or a `MultiPreview` from Flutter, or a subclass of either',
    () async {
      final root = Directory.systemTemp.createTempSync('ciach_previews_');
      addTearDown(() => root.deleteSync(recursive: true));
      void write(String path, String contents) => File(p.join(root.path, path))
        ..createSync(recursive: true)
        ..writeAsStringSync(contents);
      // A stand-in for the library of Flutter that declares the classes.
      write('flutter/lib/src/widget_previews/widget_previews.dart', '''
base class Preview {
  const Preview();
}

abstract base class MultiPreview {
  const MultiPreview();
}
''');
      write('flutter/lib/widget_previews.dart', '''
export 'src/widget_previews/widget_previews.dart';
''');
      write(
        'app/.dart_tool/package_config.json',
        packageConfig({'app': '.', 'flutter': '../flutter'}),
      );
      write('app/pubspec.yaml', '''
name: app
environment: {sdk: ^3.13.0}
''');
      write('app/lib/previews.dart', '''
import 'package:flutter/widget_previews.dart';

final class DarkPreview extends Preview {
  const DarkPreview();
}

final class ThemePreviews extends MultiPreview {
  const ThemePreviews();
}

@Preview()
String buttonPreview() => 'OK';

@DarkPreview()
String darkButtonPreview() => 'OK';

@ThemePreviews()
String themedButtonPreview() => 'OK';

String notAPreview() => 'OK';
''');

      final result = await Ciach(
        .new(rootPath: p.join(root.path, 'app')),
      ).run();

      expect(result.unused.map((d) => d.qualifiedName), ['notAPreview']);
    },
  );
}
