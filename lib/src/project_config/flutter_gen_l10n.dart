import 'dart:io';

import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// Returns the files that `gen-l10n` generates, as `l10n.yaml` configures
/// them. `gen-l10n` writes the template file, and next to it one
/// `<template>_<locale>.dart` file for each locale. These files have no banner
/// that marks them as generated, so they have to be found this way.
/// With `synthetic-package`, `gen-l10n` writes the files into `.dart_tool/`
/// instead, so there is nothing to find in the source tree.
({Translations template, String localesGlob})? readGenL10n(String rootPath) {
  final file = File(p.join(rootPath, 'l10n.yaml'));
  if (!file.existsSync()) {
    return null;
  }
  final config = readYamlMap(file.path);
  if (config case {'synthetic-package': true}) {
    return null;
  }
  String setting(String key, String fallback) => switch (config?[key]) {
    final String value => value,
    _ => fallback,
  };
  final arbDir = setting('arb-dir', 'lib/l10n');
  final outputDir = setting('output-dir', arbDir);
  final outputFile = setting(
    'output-localization-file',
    'app_localizations.dart',
  );
  final templateArb = setting('template-arb-file', 'app_en.arb');
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
