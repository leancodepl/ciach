import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/project_config/analysis_server_plugin.dart';
import 'package:ciach/src/project_config/build_runner.dart';
import 'package:ciach/src/project_config/build_yaml.dart';
import 'package:ciach/src/project_config/custom_lint.dart';
import 'package:ciach/src/project_config/dart_frog.dart';
import 'package:ciach/src/project_config/flutter_gen_l10n.dart';
import 'package:ciach/src/project_config/flutter_plugin.dart';
import 'package:ciach/src/project_config/flutter_widget_previews.dart';
import 'package:ciach/src/project_config/flutterfire.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/project_config/serverpod.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// The entry points and generated files that are declared in a project's
/// pubspec.yaml, build.yaml and l10n.yaml. Files that cannot be parsed are
/// ignored. `Ciach` does not read the project config by itself, so pass
/// [entryPoints] and [generatedGlobs] to `FinderOptions`.
final class ProjectConfig {
  const ProjectConfig({
    this.entryPoints = const [],
    this.generatedGlobs = const [],
    this.translations = const [],
  });

  /// Reads the package at [rootPath] and every package that is nested in it,
  /// such as the members of a pub workspace. Each package is read from its own
  /// files.
  factory ProjectConfig.read(String rootPath) {
    final dirs = packageDirs(rootPath).toList();
    final pluginDirs = {
      for (final dir in dirs) ...analyzerPluginDirs(p.join(rootPath, dir)),
    };
    final packages = [
      for (final dir in dirs)
        ProjectConfig._package(
          p.normalize(p.join(rootPath, dir)),
          pluginDirs: pluginDirs,
        )._within(dir),
    ];
    return ProjectConfig(
      entryPoints: packages.expand((package) => package.entryPoints).toList(),
      generatedGlobs: packages
          .expand((package) => package.generatedGlobs)
          .toSet()
          .toList(),
      translations: packages.expand((package) => package.translations).toList(),
    );
  }

  /// Reads the package at [packagePath]. [pluginDirs] are the directories of
  /// the packages that an `analysis_options.yaml` under the root loads as
  /// plugins.
  factory ProjectConfig._package(
    String packagePath, {
    required Set<String> pluginDirs,
  }) {
    final pubspec = readPubspec(packagePath);
    final buildYamls = readBuildYamls(packagePath);
    final genL10n = readGenL10n(packagePath);
    return ProjectConfig(
      entryPoints: {
        for (final rule in [
          ...flutterPluginEntryPoints(pubspec),
          ...flutterWidgetPreviewEntryPoints(pubspec),
          for (final buildYaml in buildYamls)
            ...buildRunnerEntryPoints(pubspec, buildYaml),
          ...dartFrogEntryPoints(pubspec),
          ...serverpodEntryPoints(pubspec),
          ...analysisServerPluginEntryPoints(
            pubspec,
            loadedAsPlugin: pluginDirs.contains(packagePath),
          ),
          ...customLintEntryPoints(pubspec),
        ])
          '$rule': rule,
      }.values.toList(),
      generatedGlobs: {
        ...buildRunnerGeneratedGlobs(packagePath, pubspec, buildYamls),
        ?genL10n?.localesGlob,
        if (genL10n != null) escapeGlob(genL10n.template.dartFile),
        ...flutterFireGeneratedGlobs(packagePath),
      }.toList(),
      translations: [?genL10n?.template],
    );
  }

  static const none = ProjectConfig();

  final List<EntryPoint> entryPoints;

  /// POSIX globs that are relative to the scanned root. They also match the
  /// Dart files of [translations].
  final List<String> generatedGlobs;

  final List<Translations> translations;

  List<String> get generatedGlobsExceptTranslations {
    final templates = {for (final t in translations) escapeGlob(t.dartFile)};
    return generatedGlobs.whereNot(templates.contains).toList();
  }

  /// Returns this config of the package in [dir], with its paths made
  /// relative to the scanned root. [dir] is relative to the scanned root, and
  /// `''` stands for the root itself.
  ProjectConfig _within(String dir) {
    final prefix = escapeGlob(dir);
    return .new(
      entryPoints: [for (final e in entryPoints) e.within(prefix)],
      generatedGlobs: [
        for (final glob in generatedGlobs) p.posix.join(prefix, glob),
      ],
      translations: [
        for (final t in translations)
          (
            dartFile: p.posix.join(dir, t.dartFile),
            arbFile: p.posix.join(dir, t.arbFile),
          ),
      ],
    );
  }
}
