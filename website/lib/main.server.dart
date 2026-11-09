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
String _ciachVersion() =>
    ['../pubspec.yaml', 'pubspec.yaml']
        .map(File.new)
        .where((file) => file.existsSync())
        .map((file) => file.readAsStringSync())
        .where(_ciachName.hasMatch)
        .map((source) => _version.firstMatch(source)?.namedGroup('version'))
        .nonNulls
        .firstOrNull ??
    (throw StateError(
      'No ciach pubspec.yaml found; build from the repository.',
    ));

final _ciachName = RegExp(r'^name:\s*ciach\s*$', multiLine: true);
final _version = RegExp(r'^version:\s*(?<version>\S+)', multiLine: true);
