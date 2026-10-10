import 'dart:io';

import 'package:ciach/src/project_config/build_extensions.dart';
import 'package:ciach/src/project_config/project_config.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = .systemTemp.createTempSync('ciach_project_config_test_');
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  void write(String relativePath, String content) {
    File(p.join(tempDir.path, p.joinAll(p.posix.split(relativePath))))
      ..createSync(recursive: true)
      ..writeAsStringSync(content);
  }

  ProjectConfig read() => .read(tempDir.path);

  Set<String> rules(ProjectConfig config) => {
    for (final rule in config.entryPoints) '$rule',
  };

  bool generated(List<String> globs, String path) => globs.any(
    (glob) => Glob(glob, context: p.Context(style: .posix)).matches(path),
  );

  test('a file that does not parse is ignored', () {
    write('pubspec.yaml', 'name: [unclosed');
    write('build.yaml', '- a list');

    expect(read().entryPoints, isEmpty);
    expect(read().generatedGlobs, isEmpty);
  });

  test('plugin classes: dartPluginClass, and pluginClass on web only', () {
    write('pubspec.yaml', '''
name: my_plugin
flutter:
  plugin:
    platforms:
      android: {pluginClass: MyPluginJava}
      linux: {dartPluginClass: MyPluginLinux, dartFileName: src/linux.dart}
      windows: {dartPluginClass: MyPluginWindows, pluginClass: MyPluginCpp}
      web: {pluginClass: MyPluginWeb, fileName: my_plugin_web.dart}
''');

    expect(rules(read()), {
      'MyPluginLinux.registerWith in lib/src/linux.dart',
      'MyPluginWindows.registerWith in lib/**',
      'MyPluginWeb.registerWith in lib/my_plugin_web.dart',
    });
  });

  test('frameworks and plugins, by dependency', () {
    write('pubspec.yaml', '''
name: my_lints
dependencies: {dart_frog: any, analysis_server_plugin: any}
dev_dependencies: {serverpod: any, custom_lint_builder: any}
''');

    expect(rules(read()), {
      'onRequest in routes/**',
      'middleware in routes/**_middleware.dart',
      'init in main.dart',
      'run in main.dart',
      'public methods of `Endpoint` subclasses',
      'plugin in lib/main.dart',
      'createPlugin in lib/my_lints.dart',
    });
  });

  group('build.yaml', () {
    test('builder factories imported from this package are entry points', () {
      write('pubspec.yaml', 'name: my_gen');
      write('build.yaml', '''
builders:
  my_builder:
    import: package:my_gen/builder.dart
    builder_factories: [myBuilder, otherBuilder]
    build_extensions: {.dart: [.my.dart]}
    auto_apply: root_package
    build_to: source
  foreign: {import: package:other/builder.dart, builder_factories: [foreign]}
post_process_builders:
  cleanup: {import: package:my_gen/src/cleanup.dart, builder_factory: cleanup}
''');

      final config = read();
      expect(rules(config), {
        'myBuilder in lib/builder.dart',
        'otherBuilder in lib/builder.dart',
        'cleanup in lib/src/cleanup.dart',
      });
      expect(config.generatedGlobs, ['**.my.dart']);
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
        write('pubspec.yaml', 'name: app\ndev_dependencies: {gen: any}\n');
        write('deps/gen/build.yaml', '''
builders:
  dependents: {auto_apply: dependents, build_to: source, build_extensions: {.dart: [.dependents.dart]}}
  to_cache: {auto_apply: dependents, applies_builders: [gen|combining], build_extensions: {.dart: [.cache.dart]}}
  combining: {build_to: source, build_extensions: {.dart: [.combined.dart]}}
  own_tests_only: {auto_apply: root_package, build_to: source, build_extensions: {.dart: [.internal.dart]}}
  opt_in: {build_to: source, build_extensions: {.dart: [.opt_in.dart]}}
  gen: {build_to: source, build_extensions: {.dart: [.gen.x.dart]}}
''');
      });

      test('by auto_apply, and the builders they apply', () {
        final config = read();
        expect(config.generatedGlobs.toSet(), {
          '**.dependents.dart',
          '**.combined.dart',
        });
        expect(config.entryPoints, isEmpty);
      });

      test('none by auto_apply when the targets opt out', () {
        write('build.yaml', r'''
targets:
  $default:
    auto_apply_builders: false
    builders:
      gen|opt_in:
''');

        expect(read().generatedGlobs, ['**.opt_in.dart']);
      });

      test('dependents only for a direct dependency', () {
        write('pubspec.yaml', 'name: app\ndependencies: {other: any}\n');

        expect(read().generatedGlobs, isEmpty);
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
template-arb-file: app_pl.arb
''');

      final config = read();
      final globs = config.generatedGlobs;
      expect(globs, ['lib/src/gen/l10n_*.dart', 'lib/src/gen/l10n.dart']);
      expect(config.translations, [
        (dartFile: 'lib/src/gen/l10n.dart', arbFile: 'lib/l10n/app_pl.arb'),
      ]);
      expect(config.generatedGlobsExceptTranslations, [
        'lib/src/gen/l10n_*.dart',
      ]);
      expect(generated(globs, 'lib/src/gen/l10n_pt_BR.dart'), isTrue);
    });

    test('defaults to app_localizations.dart in the arb-dir', () {
      write('l10n.yaml', 'arb-dir: lib/i18n\n');
      expect(read().translations, [
        (
          dartFile: 'lib/i18n/app_localizations.dart',
          arbFile: 'lib/i18n/app_en.arb',
        ),
      ]);
    });

    test('a synthetic package writes nothing to the source tree', () {
      write('l10n.yaml', 'synthetic-package: true\n');
      expect(read().generatedGlobs, isEmpty);
    });
  });

  test("nested packages' config, scoped to their directory", () {
    write('pubspec.yaml', 'name: ws\nworkspace: [pkgs/app, pkgs/plugin]\n');
    write('pkgs/app/pubspec.yaml', 'name: app\ndependencies: {serverpod: any}');
    write('pkgs/app/l10n.yaml', 'output-localization-file: strings.dart\n');
    write('pkgs/plugin/pubspec.yaml', '''
name: plugin
flutter: {plugin: {platforms: {linux: {dartPluginClass: LinuxPlugin}}}}
''');
    write(
      'build/pubspec.yaml',
      'name: skipped\ndependencies: {dart_frog: any}',
    );

    final config = read();
    expect(rules(config), {
      'public methods of `Endpoint` subclasses in pkgs/app/**',
      'LinuxPlugin.registerWith in pkgs/plugin/lib/**',
    });
    expect(config.generatedGlobs, [
      'pkgs/app/lib/l10n/strings_*.dart',
      'pkgs/app/lib/l10n/strings.dart',
    ]);
    expect(config.translations.single.arbFile, 'pkgs/app/lib/l10n/app_en.arb');
  });

  test('every build.<name>.yaml counts, as build_runner --config picks it', () {
    write('pubspec.yaml', 'name: app');
    write('build.release.yaml', r'''
targets:
  $default:
    builders:
      source_gen|combining_builder:
        options:
          build_extensions: {'^lib/{{}}.dart': 'lib/gen/{{}}.g.dart'}
''');
    write('build.yaml', '''
builders:
  stamp: {import: package:app/builder.dart, builder_factories: [stamp]}
''');
    write('build.release.yaml.bak', 'not: [a config');

    final config = read();
    expect(config.generatedGlobs, ['lib/gen/**.g.dart']);
    expect(rules(config), {'stamp in lib/builder.dart'});
  });
}
