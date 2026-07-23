/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/models.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Position, SymbolKind;

/// Symbol kinds that introduce a lexical scope; their name becomes the
/// container for nested members.
const typeLikeKinds = <SymbolKind>{.class$, .interface$, .enum$, .struct};

/// Names of Dart's overloadable operators. The analysis server reports an
/// `operator +`/`operator ==`/… declaration as a plain [SymbolKind.method]
/// named exactly one of these — there is no distinct operator symbol kind —
/// so this is the only reliable way to recognize one.
const _operatorNames = <String>{
  '+',
  '-',
  '*',
  '/',
  '%',
  '~/',
  '&',
  '|',
  '^',
  '~',
  '<<',
  '>>',
  '>>>',
  '<',
  '<=',
  '>',
  '>=',
  '==',
  '[]',
  '[]=',
};

/// Symbol-shape predicates and naming rules, kept off the finder so the
/// classification logic reads as intent rather than mechanics.
extension SymbolChecks on DocumentSymbol {
  /// Whether this is an operator overload (`operator +`, `operator ==`, …).
  bool get isOperator => kind == .method && _operatorNames.contains(name);

  /// Whether this is a `call` method (callable via implicit-call syntax
  /// `obj(...)`). The reference search can't resolve that syntax back to the
  /// declaration — like an infix operator — so a used `call` reads as unused.
  bool get isCallMethod => kind == .method && name == 'call';

  /// Whether this is a private constructor (`Foo._`, `Foo._named`). The server
  /// names constructors with the class included (`Foo`, `Foo.named`), so the
  /// private marker is a segment after the last `.` starting with `_`; the
  /// unnamed constructor (no `.`) is never private here.
  bool get isPrivateConstructor {
    if (kind != .constructor) {
      return false;
    }
    final dot = name.lastIndexOf('.');
    return dot >= 0 && dot + 1 < name.length && name[dot + 1] == '_';
  }

  /// Whether the parameter list is empty. The server reports the signature in
  /// [DocumentSymbol.detail] as the parenthesized parameter list (`()`,
  /// `(int a)`, …); if the detail is missing we can't tell the arity, so treat
  /// it as empty to avoid missing the zero-parameter marker.
  bool get hasNoParameters {
    final detail = this.detail?.trim();
    if (detail == null || detail.isEmpty) {
      return true;
    }
    final inner = detail.startsWith('(') && detail.endsWith(')')
        ? detail.substring(1, detail.length - 1).trim()
        : detail;
    return inner.isEmpty;
  }

  /// Whether this is the classic prevent-instantiation marker: a class's sole,
  /// zero-parameter private constructor (`Foo._();`). [siblings] are the
  /// constructor's fellow class members, used to confirm it is the class's
  /// only constructor.
  bool isPreventInstantiationMarker(List<DocumentSymbol> siblings) =>
      isPrivateConstructor &&
      siblings.where((s) => s.kind == .constructor).length == 1 &&
      hasNoParameters;

  /// The kind ciach reports for this symbol. The analysis server tags enum
  /// values with [SymbolKind.enum$] (same as the enum type), so remap them to
  /// [SymbolKind.enumMember] under an enum to match the `enum-value` CLI kind.
  SymbolKind reportedKind({required bool parentIsEnum}) =>
      parentIsEnum && kind == .enum$ ? .enumMember : kind;

  /// The name to report for this symbol.
  ///
  /// The analysis server names constructor symbols with the class included
  /// (`Foo` for the unnamed constructor, `Foo.named` for a named one). The
  /// [container] already carries the class, so strip that prefix and report the
  /// unnamed constructor as `new` — yielding `Foo.named` / `Foo.new` once
  /// combined with the container, rather than `Foo.Foo.named` / `Foo.Foo`.
  String declarationName(String? container) {
    if (kind != .constructor) {
      return name;
    }
    if (container != null && name.startsWith('$container.')) {
      return name.substring(container.length + 1);
    }
    return name.isEmpty || name == container ? 'new' : name;
  }

  /// The full source span of this symbol (including its body).
  DeclarationRange get declarationRange => (
    startLine: range.start.line,
    startColumn: range.start.character,
    endLine: range.end.line,
    endColumn: range.end.character,
  );

  /// The first line of this symbol including its contiguous leading
  /// doc-comment/annotation block (mirrors the removal-side extension), so a
  /// self-referencing dartdoc link in the class's own doc counts as a
  /// self-reference.
  int metadataTopLine(List<String> lines) {
    final nameLine = selectionRange.start.line;
    var top = range.start.line <= nameLine ? range.start.line : nameLine;
    while (top - 1 >= 0 && _looksLikeMetadata(lines[top - 1].trim())) {
      top--;
    }
    return top;
  }

  /// The annotations, modifiers and doc comments immediately preceding this
  /// symbol, as a single string, for cheap annotation detection.
  String leadingMetadata(List<String> lines) {
    final nameLine = selectionRange.start.line;
    final top = metadataTopLine(lines);
    final end = nameLine < lines.length ? nameLine : lines.length - 1;
    return lines.sublist(top, end + 1).join('\n');
  }
}

/// Position geometry against a symbol's source range.
extension PositionGeometry on Position {
  /// Whether this position is at or before [end].
  bool atOrBefore(Position end) =>
      line < end.line || (line == end.line && character <= end.character);

  /// Whether this position falls within [symbol]'s full source range.
  bool within(DocumentSymbol symbol) {
    final start = symbol.range.start;
    final afterStart =
        line > start.line ||
        (line == start.line && character >= start.character);
    return afterStart && atOrBefore(symbol.range.end);
  }
}

/// Whether [name] (possibly qualified, e.g. `Foo._bar`) is library-private —
/// its simple segment starts with `_`.
bool isPrivateName(String name) =>
    (name.contains('.') ? name.split('.').last : name).startsWith('_');

bool _looksLikeMetadata(String trimmedLine) =>
    trimmedLine.isEmpty ||
    trimmedLine.startsWith('@') ||
    trimmedLine.startsWith('//') ||
    trimmedLine.startsWith('/*') ||
    trimmedLine.startsWith('*') ||
    trimmedLine.endsWith('*/');
