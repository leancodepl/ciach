/// Server entrypoint: runs once during `jaspr build` to pre-render every route.
library;

import 'dart:io';

import 'package:ciach_website/app.dart';
import 'package:ciach_website/highlight.dart';
import 'package:ciach_website/main.server.options.dart';
import 'package:jaspr/server.dart';

Future<void> main() async {
  Jaspr.initializeApp(options: defaultServerOptions);
  await initHighlighting();

  runApp(App(version: _ciachVersion()));
}

/// The ciach version, read from the package's own pubspec so the site can
/// never announce a stale number.
String _ciachVersion() {
  for (final candidate in ['../pubspec.yaml', 'pubspec.yaml']) {
    final file = File(candidate);
    if (!file.existsSync()) {
      continue;
    }
    final source = file.readAsStringSync();
    if (!RegExp(r'^name:\s*ciach\s*$', multiLine: true).hasMatch(source)) {
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
  throw StateError('No ciach pubspec.yaml found; build from the repository.');
}
