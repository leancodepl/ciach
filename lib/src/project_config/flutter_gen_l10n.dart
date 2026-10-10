import 'dart:io';

import 'package:ciach/src/conventions/gen_l10n.dart';
import 'package:ciach/src/project_config/project_files.dart';
import 'package:path/path.dart' as p;

/// The files gen-l10n generates, read from `l10n.yaml`: the template file, and
/// one `<template>_<locale>.dart` per locale beside it. They have no
/// generated-code banner, so they are found this way. This follows Flutter up
/// to 1.22, the version that added `output-dir`. With `synthetic-package`,
/// gen-l10n writes into `.dart_tool/` instead, so there is nothing to find.
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
