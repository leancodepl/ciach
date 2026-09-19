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
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Position, Range, SymbolKind;

/// Symbol kinds that introduce a lexical scope; their name becomes the
/// container for nested members. [SymbolKind.namespace] is an extension.
const typeLikeKinds = <SymbolKind>{.class$, .interface$, .enum$, .namespace};

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

  /// Whether this is a primary constructor's `this : …` body part, which the
  /// server reports as a constructor named `this` — a name no ordinary
  /// constructor can have.
  bool get isPrimaryConstructorBody => kind == .constructor && name == 'this';

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
  SymbolKind reportedKind({
    required bool parentIsEnum,
    bool isExtensionType = false,
  }) => switch (kind) {
    .enum$ when parentIsEnum => .enumMember,
    .namespace when isExtensionType => .struct,
    _ => kind,
  };

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

  /// The symbol's code, body included.
  DeclarationRange get declarationRange => range.toDeclarationRange;
}

extension RangeConversion on Range {
  /// This range as a [DeclarationRange].
  DeclarationRange get toDeclarationRange => (
    startLine: start.line,
    startColumn: start.character,
    endLine: end.line,
    endColumn: end.character,
  );
}

/// The last of [items] starting at or before [position], or `null` when none
/// does. [items] must be in source order, as the analysis server reports
/// declarations, which makes this a binary search.
T? lastStartingAtOrBefore<T>(
  List<T> items,
  Position position,
  Position Function(T item) startOf,
) {
  var lo = 0;
  var hi = items.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (startOf(items[mid]).atOrBefore(position)) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo == 0 ? null : items[lo - 1];
}

/// Position geometry against a symbol's source range.
extension PositionGeometry on Position {
  /// Whether this position is at or before [end].
  bool atOrBefore(Position end) =>
      line < end.line || (line == end.line && character <= end.character);

  /// Whether this position is before [other].
  bool isBefore(Position other) =>
      line < other.line || (line == other.line && character < other.character);

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
