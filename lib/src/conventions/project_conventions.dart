import 'package:ciach/src/conventions/analysis_server_plugin.dart';
import 'package:ciach/src/conventions/build_runner.dart';
import 'package:ciach/src/conventions/custom_lint.dart';
import 'package:ciach/src/conventions/dart_frog.dart';
import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/flutter_gen_l10n.dart';
import 'package:ciach/src/conventions/flutter_plugin.dart';
import 'package:ciach/src/conventions/project_files.dart';
import 'package:ciach/src/conventions/serverpod.dart';

/// Entry points and generated files declared by pubspec.yaml, build.yaml and
/// l10n.yaml. Unparsable files are ignored.
final class ProjectConventions {
  const ProjectConventions({
    this.entryPoints = const [],
    this.generatedGlobs = const [],
  });

  factory ProjectConventions.read(String rootPath) {
    final pubspec = readPubspec(rootPath);
    final buildYaml = readBuildYaml(rootPath);
    return ProjectConventions(
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

  static const none = ProjectConventions();

  final List<EntryPoint> entryPoints;

  /// POSIX, relative to the package root.
  final List<String> generatedGlobs;
}
