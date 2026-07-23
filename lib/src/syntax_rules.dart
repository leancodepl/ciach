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
import 'package:ciach/src/lexing.dart';
import 'package:ciach/src/source_index.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// The lexer token at a resolved reference: the file's token stream plus the
/// index of the referenced type name.
typedef _TypeToken = ({List<Token> tokens, int ti});

/// Structural, lexer-level checks over a declaration or a reference — the
/// syntactic special cases the reference classifier layers on top of the raw
/// "has references?" verdict. They run over the cached token stream in
/// [SourceIndex], never a full parse, and are deliberately conservative: when
/// a shape can't be confirmed they answer in the direction that keeps code.
extension StructuralChecks on SourceIndex {
  /// Whether [ctor] is a redirecting factory (`factory X(..) = Target;`) — a
  /// `=` at depth 0 after `factory` whose next token is a word (not a `=>`
  /// body).
  bool isRedirectingFactory(Candidate ctor) {
    final window = tokenWindow(ctor.path, ctor.symbol);
    if (window == null) {
      return false;
    }
    final (:tokens, :start, :end) = window;
    var sawFactory = false;
    var depth = 0;
    for (var i = start; i < end; i++) {
      final t = tokens[i];
      if (t.isWord) {
        if (t.value == 'factory') {
          sawFactory = true;
        }
      } else if (t.isOpener) {
        depth++;
      } else if (t.isCloser) {
        depth--;
      } else if (t.value == '=' &&
          depth == 0 &&
          sawFactory &&
          i + 1 < tokens.length &&
          tokens[i + 1].isWord) {
        return true;
      }
    }
    return false;
  }

  /// Whether [ctor] forwards to a super constructor *with arguments* — a
  /// `super.<field>` parameter or a non-empty `super(...)` call. Such a
  /// constructor exists to satisfy a superclass whose unnamed constructor is
  /// not zero-arg; removing it (leaving an implicit default constructor that
  /// calls `super()`) would fail to compile (`no_default_super_constructor`).
  /// A bare `super()` is not forwarding.
  ///
  /// Deliberately conservative: a `super.method()` call in the body is also
  /// treated as forwarding, which can over-block a safe removal — the tool
  /// reports the finding rather than risk a build break.
  bool ctorForwardsSuper(Candidate ctor) {
    final window = tokenWindow(ctor.path, ctor.symbol);
    if (window == null) {
      return false;
    }
    final (:tokens, :start, :end) = window;
    for (var i = start; i < end; i++) {
      final t = tokens[i];
      if (!t.isWord || t.value != 'super' || i + 1 >= tokens.length) {
        continue;
      }
      final next = tokens[i + 1];
      if (next.isWord) {
        continue;
      }
      switch (next.value) {
        case '.':
          return true;
        case '(':
          final after = i + 2 < tokens.length ? tokens[i + 2] : null;
          final emptyCall =
              after != null && !after.isWord && after.value == ')';
          if (!emptyCall) {
            return true;
          }
      }
    }
    return false;
  }

  /// Whether [classCandidate] declares at least one `final` *instance* field
  /// (not `static`/`const`). Such a field relies on a constructor to be
  /// initialized, so removing the class's sole constructor would strand it
  /// (`final_not_initialized`).
  bool classHasFinalInstanceField(Candidate classCandidate) =>
      (classCandidate.symbol.children ?? const []).any(
        (child) =>
            child.kind == .field &&
            _isFinalInstanceField(classCandidate.path, child),
      );

  /// Whether [field] in [path] is declared `final` and is an *instance* field,
  /// determined by scanning the declaration's modifier/type prefix — the tokens
  /// between the field name and the enclosing class body `{` or the previous
  /// member's terminating `;`. A `static` or `const` modifier disqualifies it
  /// (those don't depend on a constructor).
  bool _isFinalInstanceField(String path, DocumentSymbol field) {
    final ti = tokenIndexAtPosition(path, field.selectionRange.start);
    if (ti == null) {
      return false;
    }
    final toks = tokens(path);
    var isFinal = false;
    var depth = 0;
    for (var i = ti - 1; i >= 0; i--) {
      final t = toks[i];
      if (t.isWord) {
        if (t.value == 'static' || t.value == 'const') {
          return false;
        }
        if (t.value == 'final') {
          isFinal = true;
        }
      } else if (t.isCloser) {
        depth++;
      } else if (t.isOpener) {
        // A `{` at depth 0 is the class body's opening brace, and an unmatched
        // `(`/`[` there means the prefix's start — either way, the field
        // declaration begins here.
        if (depth == 0) {
          return isFinal;
        }
        depth--;
      } else if (t.value == ';' && depth == 0) {
        return isFinal; // previous member/statement boundary
      }
    }
    return isFinal;
  }

  /// Whether [enumCandidate] iterates its own values via the implicit `values`
  /// getter from inside its body — a bare `values` (not `x.values`), as in a
  /// `values.any(…)` helper. Having no `<EnumName>.` prefix, it's invisible to a
  /// references query on the type ([isDotValuesRef]), so it's found by a source
  /// scan. Conservative: a local named `values` also matches, which only ever
  /// retains code, never removes something live.
  bool enumIteratesOwnValues(Candidate enumCandidate) {
    final window = tokenWindow(enumCandidate.path, enumCandidate.symbol);
    if (window == null) {
      return false;
    }
    final (:tokens, :start, :end) = window;
    for (var i = start; i < end; i++) {
      final t = tokens[i];
      if (!t.isWord || t.value != 'values') {
        continue;
      }
      // `.values` here is member access on another receiver, not the enum's own
      // getter; the qualified form is handled by [isDotValuesRef].
      final prev = i > 0 ? tokens[i - 1] : null;
      if (prev != null && !prev.isWord && prev.value == '.') {
        continue;
      }
      return true;
    }
    return false;
  }

  /// Whether reference [loc] is a type name immediately followed by `.values`
  /// — the qualified `<EnumName>.values` iteration, which reaches every value.
  /// The implicit bare-`values` form is caught by [enumIteratesOwnValues].
  /// Precise on purpose: a `.value` access or a `.values` on another symbol
  /// doesn't count.
  bool isDotValuesRef(Location loc) {
    final located = _locateTypeToken(loc);
    if (located == null) {
      return false;
    }
    final (:tokens, :ti) = located;
    if (ti + 2 >= tokens.length) {
      return false;
    }
    final dot = tokens[ti + 1];
    final values = tokens[ti + 2];
    return !dot.isWord &&
        dot.value == '.' &&
        values.isWord &&
        values.value == 'values';
  }

  /// Whether reference [loc] to a class is a *type pattern* — a match, not a
  /// construction — for the opt-in dead-union-member detection.
  ///
  /// Recognized as patterns:
  ///
  /// * A `case <Type>` pattern — in a `switch` statement, or in an
  ///   `if (x case …)` / `while (x case …)` header.
  /// * A switch-*expression* arm `<Type>… => …,`.
  ///
  /// Everything else (construction, type annotations, `extends`/`implements`,
  /// static access, nested sub-patterns, pattern-variable declarations) is not
  /// a pattern — a real use that keeps the class alive.
  bool isPatternRef(Location loc) {
    final located = _locateTypeToken(loc);
    if (located == null) {
      return false;
    }
    final (:tokens, :ti) = located;
    final prev = ti > 0 ? tokens[ti - 1] : null;
    // Any `case <Type>` — switch statement, if-case, or while-case — matches
    // the type without constructing it.
    if (prev != null && prev.isWord && prev.value == 'case') {
      return true;
    }
    return _isSwitchExprArm(tokens, ti);
  }

  /// Resolves [loc] to the lexer token index of the referenced type name,
  /// returning it with the file's cached tokens, or `null` if the reference
  /// doesn't line up with a word token.
  _TypeToken? _locateTypeToken(Location loc) {
    final path = SourceIndex.pathOf(loc.uri);
    final ti = tokenIndexAtPosition(path, loc.range.start);
    if (ti == null) {
      return null;
    }
    final toks = tokens(path);
    return toks[ti].isWord ? (tokens: toks, ti: ti) : null;
  }

  /// Whether the type token at [ti] begins a switch-*expression* arm: preceded
  /// by the `{`/`,` of a `switch (…) {` body and followed by a top-level `=>`.
  bool _isSwitchExprArm(List<Token> tokens, int ti) {
    if (ti == 0) {
      return false;
    }
    final prev = tokens[ti - 1];
    if (prev.isWord || (prev.value != '{' && prev.value != ',')) {
      return false;
    }
    // Find the enclosing `{` (walking back over a preceding arm if prev is `,`).
    final braceIndex = enclosingOpener(tokens, ti - 1);
    if (braceIndex == null || tokens[braceIndex].value != '{') {
      return false;
    }
    // `{` must close a `switch (…)` header: the token before it is `)` whose
    // matching `(` is immediately preceded by `switch`.
    final closeParen = braceIndex - 1;
    if (closeParen < 0 ||
        tokens[closeParen].isWord ||
        tokens[closeParen].value != ')') {
      return false;
    }
    final openParen = matchingOpenParen(tokens, closeParen);
    if (openParen == null || openParen == 0) {
      return false;
    }
    final kw = tokens[openParen - 1];
    if (!kw.isWord || kw.value != 'switch') {
      return false;
    }
    // A top-level `=>` must follow the pattern (so this is an arm, not e.g. a
    // set/map entry inside a collection literal).
    var depth = 0;
    for (var k = ti + 1; k < tokens.length; k++) {
      final t = tokens[k];
      if (t.isWord) {
        continue;
      }
      if (t.isOpener) {
        depth++;
      } else if (t.isCloser) {
        if (depth == 0) {
          return false;
        }
        depth--;
      } else if (depth == 0) {
        if (t.value == ',' || t.value == ';') {
          return false;
        }
        if (t.value == '=' &&
            k + 1 < tokens.length &&
            !tokens[k + 1].isWord &&
            tokens[k + 1].value == '>') {
          return true;
        }
      }
    }
    return false;
  }
}
