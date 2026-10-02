import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/project_config/analysis_server_plugin.dart';
import 'package:ciach/src/project_config/build_runner.dart';
import 'package:ciach/src/project_config/custom_lint.dart';
import 'package:ciach/src/project_config/dart_frog.dart';
import 'package:ciach/src/project_config/flutter_gen_l10n.dart';
import 'package:ciach/src/project_config/flutter_plugin.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/project_config/serverpod.dart';
import 'package:path/path.dart' as p;

/// Entry points and generated files declared by pubspec.yaml, build.yaml and
/// l10n.yaml. Unparsable files are ignored.
final class ProjectConfig {
  const ProjectConfig({
    this.entryPoints = const [],
    this.generatedGlobs = const [],
    this.translations = const [],
  });

  /// The package at [rootPath] and every package nested in it, like a pub
  /// workspace's members, each read from its own files.
  factory ProjectConfig.read(String rootPath) {
    final entryPoints = <EntryPoint>[];
    final generatedGlobs = <String>{};
    final translations = <Translations>[];
    for (final dir in packageDirs(rootPath)) {
      final prefix = dir.isEmpty ? '' : escapeGlob(dir);
      final package = ProjectConfig._package(p.join(rootPath, dir));
      entryPoints.addAll([
        for (final e in package.entryPoints) e.within(prefix),
      ]);
      generatedGlobs.addAll([
        for (final glob in package.generatedGlobs) p.posix.join(prefix, glob),
      ]);
      translations.addAll([
        for (final t in package.translations)
          (
            dartFile: p.posix.join(dir, t.dartFile),
            arbFile: p.posix.join(dir, t.arbFile),
          ),
      ]);
    }
    return ProjectConfig(
      entryPoints: entryPoints,
      generatedGlobs: generatedGlobs.toList(),
      translations: translations,
    );
  }

  factory ProjectConfig._package(String packagePath) {
    final pubspec = readPubspec(packagePath);
    final buildYamls = readBuildYamls(packagePath);
    final genL10n = readGenL10n(packagePath);
    return ProjectConfig(
      entryPoints: {
        for (final rule in [
          ...flutterPluginEntryPoints(pubspec),
          for (final buildYaml in buildYamls)
            ...buildRunnerEntryPoints(pubspec, buildYaml),
          ...dartFrogEntryPoints(pubspec),
          ...serverpodEntryPoints(pubspec),
          ...analysisServerPluginEntryPoints(pubspec),
          ...customLintEntryPoints(pubspec),
        ])
          '$rule': rule,
      }.values.toList(),
      generatedGlobs: {
        for (final buildYaml in buildYamls)
          ...buildRunnerGeneratedGlobs(packagePath, pubspec, buildYaml),
        ?genL10n?.localesGlob,
        if (genL10n != null) escapeGlob(genL10n.template.dartFile),
      }.toList(),
      translations: [?genL10n?.template],
    );
  }

  static const none = ProjectConfig();

  final List<EntryPoint> entryPoints;

  /// POSIX, relative to the scanned root. Includes [translations].
  final List<String> generatedGlobs;

  final List<Translations> translations;

  List<String> get generatedGlobsExceptTranslations {
    final templates = {for (final t in translations) escapeGlob(t.dartFile)};
    return [
      for (final glob in generatedGlobs)
        if (!templates.contains(glob)) glob,
    ];
  }
}
