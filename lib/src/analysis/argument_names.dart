/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';

/// Returns the name and the colon of the named argument or named record field
/// [node] when they are tokens of [node], as they are from analyzer 13.0.0
/// on: `x` and `:` in `f(x: 1)` and in `(x: 1)`. Before, the name is an
/// identifier in a [Label], and this returns `null`.
({Token name, Token colon})? argumentNameOf(AstNode node) =>
    switch (node.childEntities.first) {
      final Token name &&
          Token(next: final Token colon && Token(type: .COLON)) =>
        (name: name, colon: colon),
      _ => null,
    };
