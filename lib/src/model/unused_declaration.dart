/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/model/finder_options.dart';
import 'package:ciach/src/model/symbol_kind.dart';
import 'package:ciach/src/util/extensions.dart';

/// A `[start, end)` span of a file's content, as offsets in UTF-16 code
/// units, which is how Dart strings count characters.
///
/// Identifies the full extent of a declaration — including its body — so it
/// can be located again for removal.
typedef DeclarationRange = ({int start, int end});

/// The kinds of declaration that can share a statement with others, like `a`
/// and `b` in `int a = 1, b = 2;`. The `range` of one covers only `a = 1`, so
/// `--remove` deletes its [UnusedDeclaration.cut] instead.
const declaratorKinds = <SymbolKind>{.field, .variable};

/// A declaration to remove together with a reported one. It names its own
/// `filePath` (relative to the analyzed root, `/`-separated), so it can live in
/// another file, like a dead `StatefulWidget`'s `State` subclass.
///
/// `range`, `fullRange`, `kind` and `cut` mean what they do on
/// [UnusedDeclaration]. When `isClauseEntry` is true, the removal takes a
/// type out of a `with` or `implements` clause, like `M` out of
/// `class A with M {}`: its `kind` is the kind of that type, its `range` and
/// `fullRange` cover the entry, like `M<int>`, and its `cut` is the text that
/// `--remove` deletes, which can hold other entries too.
typedef CoupledRemoval = ({
  String filePath,
  SymbolKind kind,
  bool isClauseEntry,
  DeclarationRange range,
  DeclarationRange fullRange,
  DeclarationRange? cut,
});

/// A single declaration that the finder decided to report as unused.
class UnusedDeclaration {
  /// Creates a report entry for an unused declaration.
  const UnusedDeclaration({
    required this.name,
    required this.kind,
    required this.filePath,
    required this.line,
    required this.column,
    required this.isPrivate,
    required this.range,
    DeclarationRange? fullRange,
    this.container,
    this.coupledRemovals = const [],
    this.removalBlocked = false,
    this.hint,
    this.onlyReferencedFrom = const [],
    this.cut,
  }) : fullRange = fullRange ?? range;

  /// Simple (unqualified) name of the declaration.
  final String name;

  /// The kind of declaration (class, method, constructor, …).
  final SymbolKind kind;

  /// Path to the file, relative to the analyzed root, using `/` separators.
  final String filePath;

  /// One-based line of the declaration's name.
  final int line;

  /// One-based column of the declaration's name.
  final int column;

  /// Whether the declaration is library-private: its name or the name of the
  /// type that declares it starts with `_`, or it is an unnamed extension or
  /// one of its members.
  final bool isPrivate;

  /// Enclosing declaration name (e.g. the class for a method), if any.
  final String? container;

  /// The declaration's code, body included. For a `field`, `variable` or
  /// `constant` it covers only that declarator.
  final DeclarationRange range;

  /// [range] extended to include the doc comment and annotations.
  final DeclarationRange fullRange;

  /// For a `field`, `variable` or `constant`, the text `--remove` deletes: the
  /// whole statement when all its variables go, or this variable and one
  /// adjacent comma when others stay. `null` when the finder couldn't work it
  /// out; `--remove` then leaves the variable in place.
  final DeclarationRange? cut;

  /// Whether this is an enum value (e.g. `south` in `enum Direction`).
  /// Removing one requires also tidying up a neighboring comma, unlike other
  /// declaration kinds.
  bool get isEnumValue => kind == .enumValue;

  /// What `--remove` deletes with this declaration to keep the code
  /// compiling, though it isn't a finding of its own: a dead widget's private
  /// `State` subclass, the overrides of a dead member, and the `with` or
  /// `implements` entries that name a removed type.
  final List<CoupledRemoval> coupledRemovals;

  /// Whether `--remove` leaves this dead declaration, and what is coupled to
  /// it, in place, because removing it safely would take a source rewrite,
  /// such as for a class that only type patterns match under
  /// `--also union-members`. It is still reported.
  final bool removalBlocked;

  /// A note shown with the finding, which doesn't change how it is removed,
  /// such as a nudge toward `abstract final class` for a sole private
  /// constructor `Foo._();`.
  final String? hint;

  /// With [FinderOptions.transitive], the findings that held this
  /// declaration's only references, in source order. Empty when nothing
  /// referenced it at all.
  final List<DeadReferrer> onlyReferencedFrom;

  /// This declaration with the given fields replaced.
  UnusedDeclaration copyWith({
    DeclarationRange? cut,
    List<CoupledRemoval>? coupledRemovals,
    bool? removalBlocked,
    String? hint,
  }) => .new(
    name: name,
    kind: kind,
    filePath: filePath,
    line: line,
    column: column,
    isPrivate: isPrivate,
    range: range,
    fullRange: fullRange,
    container: container,
    coupledRemovals: coupledRemovals ?? this.coupledRemovals,
    removalBlocked: removalBlocked ?? this.removalBlocked,
    hint: hint ?? this.hint,
    onlyReferencedFrom: onlyReferencedFrom,
    cut: cut ?? this.cut,
  );

  /// Fully qualified display name, e.g. `MyClass.myMethod`.
  String get qualifiedName =>
      container?.let((container) => '$container.$name') ?? name;

  /// A JSON-encodable representation of this declaration.
  Map<String, Object?> toJson() => {
    'name': name,
    'qualifiedName': qualifiedName,
    'kind': kind.label,
    'file': filePath,
    'line': line,
    'column': column,
    'isPrivate': isPrivate,
    'container': ?container,
    'hint': ?hint,
    if (onlyReferencedFrom.isNotEmpty)
      'onlyReferencedFrom': [
        for (final referrer in onlyReferencedFrom)
          {
            'qualifiedName': referrer.qualifiedName,
            'file': referrer.filePath,
            'line': referrer.line,
          },
      ],
  };
}

/// Orders findings by file, then line, then column.
int compareByLocation(UnusedDeclaration a, UnusedDeclaration b) {
  final byFile = a.filePath.compareTo(b.filePath);
  if (byFile != 0) {
    return byFile;
  }
  final byLine = a.line.compareTo(b.line);
  return byLine != 0 ? byLine : a.column.compareTo(b.column);
}

/// A finding that references another one: its qualified name, its file
/// (root-relative, `/`-separated) and its one-based line.
typedef DeadReferrer = ({String qualifiedName, String filePath, int line});
