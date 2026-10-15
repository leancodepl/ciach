import 'dart:convert';
import 'dart:io';

import 'package:ciach/src/workspace/analysis_options.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../support/package_config.dart';

void main() {
  late Directory root;

  void write(String path, String contents) => File(p.join(root.path, path))
    ..createSync(recursive: true)
    ..writeAsStringSync(contents);

  String path(String relative) => p.normalize(p.join(root.path, relative));

  Map<String, Object?> decoded(
    Map<String, String> rewritten,
    String relative,
  ) => jsonDecode(rewritten[path(relative)]!) as Map<String, Object?>;

  setUp(() => root = .systemTemp.createTempSync('ciach_analysis_options_'));

  tearDown(() => root.deleteSync(recursive: true));

  test('drops lint rules and analyzer plugins, keeping the rest', () {
    write('analysis_options.yaml', '''
include: package:lints/recommended.yaml
analyzer:
  exclude:
    - "**.g.dart"
  enable-experiment:
    - macros
  errors:
    todo: ignore
  plugins:
    - custom_lint
linter:
  rules:
    - avoid_print
plugins:
  app_lint:
    path: packages/app_lint
''');

    expect(
      decoded(analysisOptionsWithoutLints(root.path), 'analysis_options.yaml'),
      {
        'include': 'package:lints/recommended.yaml',
        'analyzer': {
          'exclude': ['**.g.dart'],
          'enable-experiment': ['macros'],
          'errors': {'todo': 'ignore'},
        },
      },
    );
  });

  test('leaves out a file with nothing to drop', () {
    write('analysis_options.yaml', '''
analyzer:
  exclude:
    - "**.g.dart"
''');

    expect(analysisOptionsWithoutLints(root.path), isEmpty);
  });

  test('rewrites the files a relative include names', () {
    write('analysis_options.yaml', 'include: shared/base.yaml\n');
    write('shared/base.yaml', '''
include: strict.yaml
linter:
  rules:
    - avoid_print
''');
    write('shared/strict.yaml', '''
analyzer:
  language:
    strict-casts: true
linter:
  rules:
    - prefer_final_locals
''');

    final rewritten = analysisOptionsWithoutLints(root.path);

    expect(rewritten.keys, {
      path('shared/base.yaml'),
      path('shared/strict.yaml'),
    });
    expect(decoded(rewritten, 'shared/base.yaml'), {'include': 'strict.yaml'});
    expect(decoded(rewritten, 'shared/strict.yaml'), {
      'analyzer': {
        'language': {'strict-casts': true},
      },
    });
  });

  test("resolves a package: include through the project's packages", () {
    write(
      'app/.dart_tool/package_config.json',
      packageConfig({'app': '.', 'lints': '../lints'}),
    );
    write('app/analysis_options.yaml', '''
include:
  - package:lints/recommended.yaml
''');
    write('lints/lib/recommended.yaml', '''
include: package:lints/core.yaml
linter:
  rules:
    - avoid_print
''');
    write('lints/lib/core.yaml', '''
linter:
  rules:
    - prefer_final_locals
''');

    expect(analysisOptionsWithoutLints(path('app')).keys, {
      path('lints/lib/recommended.yaml'),
      path('lints/lib/core.yaml'),
    });
  });

  test(
    'finds the analysis options of nested packages, not of skipped dirs',
    () {
      const options = '''
linter:
  rules:
    - avoid_print
''';
      write('analysis_options.yaml', options);
      write('packages/core/analysis_options.yaml', options);
      write('build/analysis_options.yaml', options);
      write('.dart_tool/analysis_options.yaml', options);

      expect(analysisOptionsWithoutLints(root.path).keys, {
        path('analysis_options.yaml'),
        path('packages/core/analysis_options.yaml'),
      });
    },
  );

  test('skips a file that does not parse, and an include it cannot find', () {
    write('analysis_options.yaml', 'include: missing.yaml\nlinter: [\n');
    write('packages/core/analysis_options.yaml', '''
include: package:unknown/options.yaml
plugins:
  app_lint:
    path: ../app_lint
''');

    expect(analysisOptionsWithoutLints(root.path).keys, {
      path('packages/core/analysis_options.yaml'),
    });
  });
}
