/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:test/test.dart';

/// A [FormatException] whose message matches [message].
Matcher formatExceptionWith(Matcher message) =>
    isA<FormatException>().having((e) => e.message, 'message', message);
