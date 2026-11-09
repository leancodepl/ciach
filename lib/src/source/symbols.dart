/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/util/extensions.dart';

/// The kind and the naming rules of the declaration that an outline node
/// describes.
extension DeclarationNames on OutlineElement {
  /// The kind that reports print and `--kinds` selects, or `null` for a file
  /// or a test, which declare nothing. A mixin application class is a class,
  /// and every type alias is a typedef.
  SymbolKind? get reportedKind => switch (kind) {
    .class$ || .classTypeAlias => .class$,
    .constructor => .constructor,
    .enum$ => .enum$,
    .enumConstant => .enumValue,
    .extension => .extension,
    .extensionType => .extensionType,
    .field => .field,
    .function => .function,
    .getter || .setter => .property,
    .method => .method,
    .mixin => .mixin,
    .topLevelVariable => .variable,
    .typeAlias || .functionTypeAlias => .typedef,
    .compilationUnit || .unitTestGroup || .unitTestTest => null,
  };

  /// Whether this is a private constructor (`Foo._`, `Foo._named`). A
  /// constructor is named with the class included (`Foo`, `Foo.named`), so the
  /// private marker is a segment after the last `.` starting with `_`; the
  /// unnamed constructor (no `.`) is never private here.
  bool get isPrivateConstructor =>
      kind == .constructor && name.contains('.') && isPrivateName(name);

  /// Whether this is a primary constructor's `this : …` body part, which the
  /// outline lists as a constructor named `this` — a name no ordinary
  /// constructor can have.
  bool get isPrimaryConstructorBody => kind == .constructor && name == 'this';

  /// The name to report for this declaration.
  ///
  /// A constructor is named with the class included (`Foo` for the unnamed
  /// constructor, `Foo.named` for a named one). The [container] already
  /// carries the class, so strip that prefix and report the unnamed
  /// constructor as `new` — yielding `Foo.named` / `Foo.new` once combined
  /// with the container, rather than `Foo.Foo.named` / `Foo.Foo`.
  String declarationName(String? container) {
    if (kind != .constructor) {
      return name;
    }
    if (container != null && name.startsWith('$container.')) {
      return name.substring(container.length + 1);
    }
    return name.isEmpty || name == container ? 'new' : name;
  }

  /// The name of this declaration as the report prints it: `name` at the top
  /// level, and `Container.member` inside [container].
  String qualifiedName(String? container) =>
      container?.let(
        (container) => '$container.${declarationName(container)}',
      ) ??
      name;
}

extension OutlineChildren on Outline {
  /// The child covering [offset].
  Outline? childAt(int offset) {
    final child = lastStartingAtOrBefore(
      children,
      offset,
      (child) => child.range.start,
    );
    return child != null && offset <= child.range.end ? child : null;
  }
}

extension RangeConversion on Range {
  /// This range as a [DeclarationRange].
  DeclarationRange get toDeclarationRange => (start: start, end: end);
}

/// The last of [items] starting at or before [offset], or `null` when none
/// does. [items] must be in source order, as the outline lists declarations,
/// which makes this a binary search.
T? lastStartingAtOrBefore<T>(
  List<T> items,
  int offset,
  int Function(T item) startOf,
) {
  var lo = 0;
  var hi = items.length;
  while (lo < hi) {
    final mid = (lo + hi) >> 1;
    if (startOf(items[mid]) <= offset) {
      lo = mid + 1;
    } else {
      hi = mid;
    }
  }
  return lo == 0 ? null : items[lo - 1];
}

/// Whether [name] (possibly qualified, e.g. `Foo._bar`) is library-private —
/// its simple segment starts with `_`.
bool isPrivateName(String name) => name.split('.').last.startsWith('_');
