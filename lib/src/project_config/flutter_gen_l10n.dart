import 'dart:io';

import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// gen-l10n output has no banner.
Iterable<String> genL10nGeneratedGlobs(String rootPath) sync* {
  final file = File(p.join(rootPath, 'l10n.yaml'));
  if (!file.existsSync()) {
    return;
  }
  final config = readYamlMap(file.path) ?? const {};
  if (config['synthetic-package'] == true) {
    return;
  }
  final arbDir = switch (config['arb-dir']) {
    final String dir => dir,
    _ => 'lib/l10n',
  };
  final outputDir = switch (config['output-dir']) {
    final String dir => dir,
    _ => arbDir,
  };
  final outputFile = switch (config['output-localization-file']) {
    final String name => name,
    _ => 'app_localizations.dart',
  };
  final stem = p.posix.withoutExtension(outputFile);
  final dir = p.posix.normalize(outputDir);
  yield '${escapeGlob(dir)}/${escapeGlob(stem)}{,_*}.dart';
}
