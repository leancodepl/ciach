/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// What a site's server entrypoint needs besides the components: reading the
/// package version from its pubspec. Imports `dart:io`, so only
/// `main.server.dart` imports it.
library;

export 'src/server/pubspec_version.dart';
