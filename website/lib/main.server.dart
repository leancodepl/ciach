/// Server entrypoint: runs once during `jaspr build` to pre-render the page.
library;

import 'dart:io';

import 'package:ciach_website/app.dart';
import 'package:ciach_website/main.server.options.dart';
import 'package:ciach_website/seo.dart';
import 'package:ciach_website/site.dart';
import 'package:jaspr/server.dart';

void main() {
  Jaspr.initializeApp(options: defaultServerOptions);

  final version = _ciachVersion();

  runApp(
    Document(
      title: pageTitle,
      lang: 'en',
      base: basePath,
      meta: seoMeta,
      head: seoHead(version: version),
      body: App(version: version),
    ),
  );
}

/// The ciach version, read from the package's own pubspec so the site can
/// never announce a stale number. Falls back to a build-time define.
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
    final match = RegExp(
      r'^version:\s*(\S+)',
      multiLine: true,
    ).firstMatch(source);
    if (match != null) {
      return match[1]!;
    }
  }
  return const String.fromEnvironment('CIACH_VERSION', defaultValue: '0.4.3');
}
