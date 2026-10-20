/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'dart:io';

/// The version of the package called [name], read from the first of
/// [pubspecs] that declares it, so the site can never announce a stale
/// number. The paths are relative to the site's directory, so a build from
/// the repository root and one from the site both find the file.
String versionFromPubspec(
  String name, {
  List<String> pubspecs = const ['../pubspec.yaml', 'pubspec.yaml'],
}) {
  for (final candidate in pubspecs) {
    final file = File(candidate);
    if (!file.existsSync()) {
      continue;
    }
    final source = file.readAsStringSync();
    if (!RegExp('^name:\\s*$name\\s*\$', multiLine: true).hasMatch(source)) {
      continue;
    }
    if (RegExp(
          r'^version:\s*(?<version>\S+)',
          multiLine: true,
        ).firstMatch(source)
        case final match?) {
      return match.namedGroup('version')!;
    }
  }
  throw StateError(
    'No pubspec.yaml of $name among ${pubspecs.join(', ')}; build from the repository.',
  );
}
