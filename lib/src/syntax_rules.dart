/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source_index.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, SelectionRange;

/// Structural checks over a declaration or a reference, read from the
/// server's semantic tokens and selection ranges cached in [SourceIndex]. When
/// a check cannot confirm a shape, it answers in the direction that keeps code.
extension StructuralChecks on SourceIndex {
  /// Whether [ctor] is a redirecting factory, `factory X(..) = Target;`.
  ///
  /// Walks outwards from the constructor's last token. In a redirecting
  /// factory that reaches the declaration node directly; in a factory with a
  /// body it hits the body node first, which ends where the declaration ends.
  bool isRedirectingFactory(Candidate ctor) {
    final path = ctor.path;
    final outline = ctor.outline;
    final range = outline.codeRange;
    final tokens = semanticTokens(path)?.between(range.start, range.end);
    if (tokens == null ||
        tokens.none((t) => t.isKeyword && t.text == 'factory')) {
      return false;
    }
    final last = tokens.lastOrNull;
    if (last == null) {
      return false;
    }
    var node = selectionRangeAt(path, last.start)?.parent;
    while (node != null) {
      if (node.range == outline.range || node.range == range) {
        return true;
      }
      if (node.range.end == range.end) {
        return false; // a function body, so `=>`/`{` follows the signature
      }
      node = node.parent;
    }
    return false;
  }

  /// The last token of [ctor], where [isRedirectingFactory] needs a selection
  /// range. `null` unless [ctor] is a `factory`.
  Position? redirectProbePosition(Candidate ctor) {
    final range = ctor.outline.codeRange;
    final tokens = semanticTokens(ctor.path)?.between(range.start, range.end);
    if (tokens == null ||
        tokens.none((t) => t.isKeyword && t.text == 'factory')) {
      return null;
    }
    return tokens.lastOrNull?.start;
  }

  /// Whether [candidate] is declared in its type's header: a primary
  /// constructor (`class const Point._(…)`) or a declaring parameter
  /// (`var int x`). Removing either alone breaks the type.
  bool isDeclaredInTypeHeader(Candidate candidate) => isNameInTypeHeader(
    candidate.path,
    candidate.symbol.selectionRange.start,
    candidate.containerOutline,
  );

  /// Whether the declaration named at [position] in [path] is in [type]'s
  /// header rather than its body.
  ///
  /// Walks outwards from the name to the first node ending where the type
  /// ends: the body for a body member, the type itself for a header
  /// declaration.
  bool isNameInTypeHeader(String path, Position position, Outline? type) {
    if (type == null) {
      return false;
    }
    final end = type.codeRange.end;
    var node = selectionRangeAt(path, position);
    while (node != null && node.range.end != end) {
      node = node.parent;
    }
    return node != null &&
        (node.range == type.codeRange || node.range == type.range);
  }

  /// Whether [classCandidate] declares at least one `final` *instance* field
  /// (not `static`/`const`). Such a field relies on a constructor to be
  /// initialized, so removing the class's sole constructor would strand it
  /// (`final_not_initialized`).
  ///
  /// Only the first declarator's outline range includes the statement's
  /// modifiers (`b` in `final int a, b;` starts at its name), so the modifiers
  /// are read from that range.
  bool classHasFinalInstanceField(Candidate classCandidate) {
    final path = classCandidate.path;
    Outline? statementStart;
    for (final member in classCandidate.outline.children) {
      if (member.element.kind != .field) {
        statementStart = null;
        continue;
      }
      if (member.hasLeadingMetadata) {
        statementStart = member;
      }
      if (statementStart == null) {
        continue;
      }
      var isFinal = false;
      for (final token in leadingMetadata(path, statementStart)) {
        if (!token.isKeyword) {
          continue;
        }
        if (token.text case 'static' || 'const') {
          isFinal = false;
          break;
        }
        if (token.text == 'final') {
          isFinal = true;
        }
      }
      if (isFinal) {
        return true;
      }
    }
    return false;
  }

  /// Whether [enumCandidate] uses a bare `values` inside its body, as in
  /// `values.any(…)`. A references query on the enum does not see that use;
  /// [isDotValuesRef] covers the qualified form. A bare `values` is one whose
  /// enclosing expression starts at the token itself, not at a receiver.
  bool enumIteratesOwnValues(Candidate enumCandidate) =>
      valuesTokensIn(enumCandidate).any((token) {
        final parent = selectionRangeAt(
          enumCandidate.path,
          token.start,
        )?.parent;
        return parent != null && parent.range.start == token.start;
      });

  /// The `values` property tokens inside the body of [enumCandidate].
  Iterable<SemanticToken> valuesTokensIn(Candidate enumCandidate) {
    final range = enumCandidate.outline.codeRange;
    return semanticTokens(enumCandidate.path)
            ?.between(range.start, range.end)
            .where((t) => t.type == 'property' && t.text == 'values') ??
        const [];
  }

  /// Whether reference [loc] is an enum name followed by `.values`: the name
  /// and the `values` token form one expression node. [enumIteratesOwnValues]
  /// covers the bare form.
  bool isDotValuesRef(Location loc) {
    final path = SourceIndex.pathOf(loc.uri);
    final position = loc.range.start;
    final tokens = semanticTokens(path);
    final parent = selectionRangeAt(path, position)?.parent;
    if (tokens == null || parent == null || parent.range.start != position) {
      return false;
    }
    final last = tokens.lastIn(parent.range);
    return last != null &&
        last.type == 'property' &&
        last.text == 'values' &&
        last.start != position;
  }

  /// Whether reference [loc] to a class is a type pattern rather than a use.
  /// The nodes around it are the type, the pattern it heads (`Circle()`,
  /// `Circle c`) and the pattern's parent. It is a pattern when the parent
  /// starts with `case`, or is a switch-expression arm whose own parent starts
  /// with `switch`. Anything else, or a reference with no nodes, is a use.
  bool isPatternRef(Location loc) {
    final path = SourceIndex.pathOf(loc.uri);
    final position = loc.range.start;
    final tokens = semanticTokens(path);
    final type = selectionRangeAt(path, position);
    final pattern = type?.parent;
    final clause = pattern?.parent;
    if (tokens == null || type == null || pattern == null || clause == null) {
      return false;
    }
    if (type.range.start != position || pattern.range.start != position) {
      return false;
    }
    bool opensWith(SelectionRange node, String keyword) {
      final first = tokens.startingAt(node.range.start);
      return first != null && first.isKeyword && first.text == keyword;
    }

    if (opensWith(clause, 'case')) {
      return true;
    }
    final switchNode = clause.parent;
    return clause.range.start == position &&
        switchNode != null &&
        opensWith(switchNode, 'switch');
  }
}
