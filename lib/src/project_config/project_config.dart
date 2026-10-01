import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/project_config/analysis_server_plugin.dart';
import 'package:ciach/src/project_config/build_runner.dart';
import 'package:ciach/src/project_config/custom_lint.dart';
import 'package:ciach/src/project_config/dart_frog.dart';
import 'package:ciach/src/project_config/flutter_gen_l10n.dart';
import 'package:ciach/src/project_config/flutter_plugin.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:ciach/src/project_config/serverpod.dart';

/// Entry points and generated files declared by pubspec.yaml, build.yaml and
/// l10n.yaml. Unparsable files are ignored.
final class ProjectConfig {
  const ProjectConfig({
    this.entryPoints = const [],
    this.generatedGlobs = const [],
  });

  factory ProjectConfig.read(String rootPath) {
    final pubspec = readPubspec(rootPath);
    final buildYaml = readBuildYaml(rootPath);
    return ProjectConfig(
      entryPoints: [
        ...flutterPluginEntryPoints(pubspec),
        ...buildRunnerEntryPoints(pubspec, buildYaml),
        ...dartFrogEntryPoints(pubspec),
        ...serverpodEntryPoints(pubspec),
        ...analysisServerPluginEntryPoints(pubspec),
        ...customLintEntryPoints(pubspec),
      ],
      generatedGlobs: {
        ...buildRunnerGeneratedGlobs(rootPath, pubspec, buildYaml),
        ...genL10nGeneratedGlobs(rootPath),
      }.toList(),
    );
  }

  static const none = ProjectConfig();

  final List<EntryPoint> entryPoints;

  /// POSIX, relative to the package root.
  final List<String> generatedGlobs;
}
