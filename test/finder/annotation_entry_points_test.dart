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
import 'package:ciach/src/project_config/project_config.dart';
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

  test(
    'keeps the declarations whose annotation is a `Preview` or a `MultiPreview` from Flutter, or a subtype of either',
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
dependencies:
  flutter: {sdk: flutter}
''');
      write('app/lib/other.dart', '''
class Preview {
  const Preview();
}
''');
      write('app/lib/previews.dart', '''
import 'package:app/other.dart' as other;
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

// Not Flutter's `Preview`.
@other.Preview()
String otherPreview() => 'OK';

String notAPreview() => 'OK';
''');

      final appPath = p.join(root.path, 'app');
      final result = await Ciach(
        .new(
          rootPath: appPath,
          entryPoints: ProjectConfig.read(appPath).entryPoints,
        ),
      ).run();

      expect(result.unused.map((d) => d.qualifiedName), {
        // The `Preview` of other.dart, which only `otherPreview` uses.
        'Preview',
        'otherPreview',
        'notAPreview',
      });
    },
  );
}
