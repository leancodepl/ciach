/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';

/// [content] parsed as Dart without resolving it, also when it has syntax
/// errors: for text that no analysis context holds, such as a file that
/// `--remove` has just edited.
ParseStringResult parseDart(String content) =>
    parseString(content: content, throwIfDiagnostics: false);
