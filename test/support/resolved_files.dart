/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/lsp/dart_executable.dart';

/// The Dart files under [root], resolved with the SDK that runs the tests.
ResolvedFiles resolvedFilesUnder(String root) =>
    .new(root, sdkPath: sdkPathOf(findDartExecutable()));
