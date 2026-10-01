import 'dart:io';

import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// gen-l10n output has no banner: the template file, and one
/// `<template>_<locale>.dart` per locale beside it.
({Translations template, String localesGlob})? readGenL10n(String rootPath) {
  final file = File(p.join(rootPath, 'l10n.yaml'));
  if (!file.existsSync()) {
    return null;
  }
  final config = readYamlMap(file.path) ?? const {};
  if (config['synthetic-package'] == true) {
    return null;
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
  final templateArb = switch (config['template-arb-file']) {
    final String name => name,
    _ => 'app_en.arb',
  };
  final dir = p.posix.normalize(outputDir);
  final stem = p.posix.withoutExtension(outputFile);
  return (
    template: (
      dartFile: p.posix.join(dir, outputFile),
      arbFile: p.posix.join(p.posix.normalize(arbDir), templateArb),
    ),
    localesGlob: '${escapeGlob(dir)}/${escapeGlob(stem)}_*.dart',
  );
}
