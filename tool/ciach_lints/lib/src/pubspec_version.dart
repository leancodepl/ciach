/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/source/source_range.dart';
import 'package:analyzer/workspace/workspace.dart';
import 'package:yaml/yaml.dart';

class const PubspecVersion({
  required final String path,
  required final String value,
  required final SourceRange range,
});

/// The `version` in [package]'s `pubspec.yaml`, or `null` when there is no
/// readable pubspec or it declares no version.
PubspecVersion? readPubspecVersion(WorkspacePackage? package) {
  final pubspec = package?.root.getFile('pubspec.yaml');
  if (pubspec == null || !pubspec.exists) {
    return null;
  }
  try {
    return switch (loadYamlNode(pubspec.readAsStringSync())) {
      YamlMap(
        nodes: {'version': YamlScalar(:final String value, :final span)},
      ) =>
        .new(
          path: pubspec.path,
          value: value,
          range: .new(span.start.offset, span.length),
        ),
      _ => null,
    };
  } on YamlException {
    return null;
  }
}
