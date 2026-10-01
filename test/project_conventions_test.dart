import 'dart:io';

import 'package:ciach/src/conventions/project_conventions.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_project_conventions_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void write(String relativePath, String content) {
    File(p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  ProjectConventions read() => .read(tempDir.path);

  Set<String> rules(ProjectConventions conventions) => {
    for (final rule in conventions.entryPoints) '$rule',
  };

  /// Whether any of [globs] matches [path].
  bool generated(List<String> globs, String path) => globs.any(
    (glob) => Glob(glob, context: p.Context(style: .posix)).matches(path),
  );

  test('nothing to read, nothing declared', () {
    final conventions = read();

    expect(conventions.entryPoints, isEmpty);
    expect(conventions.generatedGlobs, isEmpty);
    expect(conventions.serverpod, isFalse);
  });

  test('a file that does not parse is ignored', () {
    write('pubspec.yaml', 'name: [unclosed');
    write('build.yaml', '- a list');
    write('l10n.yaml', 'not: [valid');

    expect(read().entryPoints, isEmpty);
  });

  group('pubspec.yaml plugin classes', () {
    test('dartPluginClass on any platform, and pluginClass on web only', () {
      write('pubspec.yaml', '''
name: my_plugin
flutter:
  plugin:
    platforms:
      android:
        package: com.example
        pluginClass: MyPluginJava
      linux:
        dartPluginClass: MyPluginLinux
        dartFileName: src/linux.dart
      windows:
        dartPluginClass: MyPluginWindows
        pluginClass: MyPluginCpp
      web:
        pluginClass: MyPluginWeb
        fileName: my_plugin_web.dart
''');

      expect(rules(read()), {
        'MyPluginLinux.registerWith in lib/src/linux.dart',
        'MyPluginWindows.registerWith in lib/**',
        'MyPluginWeb.registerWith in lib/my_plugin_web.dart',
      });
    });
  });

  group('build.yaml', () {
    test('builder factories imported from this package are entry points', () {
      write('pubspec.yaml', 'name: my_gen');
      write('build.yaml', '''
builders:
  my_builder:
    import: "package:my_gen/builder.dart"
    builder_factories: ["myBuilder", "otherBuilder"]
    build_extensions: {".dart": [".my.dart"]}
    auto_apply: root_package
    build_to: source
  foreign:
    import: "package:other/builder.dart"
    builder_factories: ["foreignBuilder"]
post_process_builders:
  cleanup:
    import: "package:my_gen/src/cleanup.dart"
    builder_factory: "cleanup"
''');

      final conventions = read();
      expect(rules(conventions), {
        'myBuilder in lib/builder.dart',
        'otherBuilder in lib/builder.dart',
        'cleanup in lib/src/cleanup.dart',
      });
      expect(conventions.generatedGlobs, ['**.my.dart']);
    });

    test('build_extensions become globs, as package:build expands them', () {
      expect(
        outputGlobs({
          '.dart': ['.g.dart', '.g.part', '.dart'],
          '^lib/config.yaml': 'lib/config.dart',
          r'$lib$': ['all.dart'],
          r'$package$': ['tool/all.dart'],
          '^lib/{{}}.dart': 'lib/generated/{{}}.g.dart',
          '{{dir}}/{{file}}.dart': ['{{dir}}/gen/{{file}}.x.dart'],
          'assets/{{}}.json': 'lib/assets/{{}}.dart',
        }).toList(),
        [
          '**.g.dart',
          'lib/config.dart',
          'lib/all.dart',
          'tool/all.dart',
          'lib/generated/**.g.dart',
          '**/gen/**.x.dart',
          '**lib/assets/**.dart',
        ],
      );
    });

    group('the builders applied to this package', () {
      setUp(() {
        write('.dart_tool/package_config.json', '''
{"configVersion": 2, "packages": [
  {"name": "app", "rootUri": "../", "packageUri": "lib/"},
  {"name": "gen", "rootUri": "../deps/gen", "packageUri": "lib/"},
  {"name": "missing", "rootUri": "../deps/missing", "packageUri": "lib/"}
]}
''');
        write('pubspec.yaml', 'name: app');
        write('deps/gen/build.yaml', '''
builders:
  dependents:
    import: "package:gen/builder.dart"
    builder_factories: ["a"]
    build_extensions: {".dart": [".dependents.dart"]}
    auto_apply: dependents
    build_to: source
  to_cache:
    import: "package:gen/builder.dart"
    builder_factories: ["b"]
    build_extensions: {".dart": [".cache.dart"]}
    auto_apply: dependents
    applies_builders: ["gen|combining"]
  combining:
    import: "package:gen/builder.dart"
    builder_factories: ["c"]
    build_extensions: {".dart": [".combined.dart"]}
    build_to: source
  own_tests_only:
    import: "tool/builder.dart"
    builder_factories: ["d"]
    build_extensions: {".dart": [".internal.dart"]}
    auto_apply: root_package
    build_to: source
  opt_in:
    import: "package:gen/builder.dart"
    builder_factories: ["e"]
    build_extensions: {".dart": [".opt_in.dart"]}
    build_to: source
  gen:
    import: "package:gen/builder.dart"
    builder_factories: ["f"]
    build_extensions: {".dart": [".gen.x.dart"]}
    build_to: source
''');
      });

      test('by auto_apply, and the builders they apply', () {
        final conventions = read();
        expect(conventions.generatedGlobs.toSet(), {
          '**.dependents.dart',
          '**.combined.dart',
        });
        // A dependency's builders are not this package's entry points.
        expect(conventions.entryPoints, isEmpty);
      });

      test('or as its targets enable and disable them', () {
        write('build.yaml', r'''
targets:
  $default:
    builders:
      gen|opt_in:
        enabled: true
      gen:
        generate_for: [lib/**]
      gen:dependents:
        enabled: false
''');

        expect(read().generatedGlobs.toSet(), {
          '**.combined.dart',
          '**.opt_in.dart',
          '**.gen.x.dart',
        });
      });
    });

    test('build_extensions given as an option relocate the output', () {
      write('build.yaml', r'''
targets:
  $default:
    builders:
      source_gen|combining_builder:
        options:
          build_extensions:
            '^lib/{{}}.dart': 'lib/generated/{{}}.g.dart'
''');

      final globs = read().generatedGlobs;
      expect(generated(globs, 'lib/generated/src/model.g.dart'), isTrue);
      expect(generated(globs, 'lib/src/model.dart'), isFalse);
    });
  });

  group('l10n.yaml', () {
    test('the output file and one per locale, in output-dir', () {
      write('l10n.yaml', '''
arb-dir: lib/l10n
output-dir: lib/src/gen/
output-localization-file: l10n.dart
''');

      final globs = read().generatedGlobs;
      expect(globs, ['lib/src/gen/l10n{,_*}.dart']);
      expect(generated(globs, 'lib/src/gen/l10n.dart'), isTrue);
      expect(generated(globs, 'lib/src/gen/l10n_pt_BR.dart'), isTrue);
      expect(generated(globs, 'lib/src/gen/strings.dart'), isFalse);
    });

    test('defaults to app_localizations.dart in the arb-dir', () {
      write('l10n.yaml', 'arb-dir: lib/i18n\n');
      expect(read().generatedGlobs, ['lib/i18n/app_localizations{,_*}.dart']);

      write('l10n.yaml', '');
      expect(read().generatedGlobs, ['lib/l10n/app_localizations{,_*}.dart']);
    });

    test('a synthetic package writes nothing to the source tree', () {
      write('l10n.yaml', 'synthetic-package: true\n');
      expect(read().generatedGlobs, isEmpty);
    });
  });

  group('frameworks, by dependency', () {
    test('dart_frog routes, middleware and server hooks', () {
      write('pubspec.yaml', '''
name: server
dependencies:
  dart_frog: ^1.0.0
''');

      expect(rules(read()), {
        'onRequest in routes/**',
        'middleware in routes/**_middleware.dart',
        'init in main.dart',
        'run in main.dart',
      });
    });

    test('analyzer and custom_lint plugins', () {
      write('pubspec.yaml', '''
name: my_lints
dependencies:
  analysis_server_plugin: any
  custom_lint_builder: any
''');

      expect(rules(read()), {
        'plugin in lib/main.dart',
        'createPlugin in lib/my_lints.dart',
      });
    });

    test('serverpod, also as a dev dependency', () {
      write('pubspec.yaml', '''
name: server
dev_dependencies:
  serverpod: any
''');

      expect(read().serverpod, isTrue);
    });
  });
}
