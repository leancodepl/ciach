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
import 'package:ciach/src/util/extensions.dart';
import 'package:pro_lsp/pro_lsp.dart' show SymbolKind;

/// A `[start, end)` span within a file, using 0-based line/column positions
/// (columns are UTF-16 code units), matching the Language Server Protocol.
///
/// Identifies the full extent of a declaration — including its body — so it
/// can be located again for removal.
typedef DeclarationRange = ({
  int startLine,
  int startColumn,
  int endLine,
  int endColumn,
});

/// The kinds of declaration that can share a statement with others, like `a`
/// and `b` in `int a = 1, b = 2;`. The `range` of one covers only `a = 1`, so
/// `--remove` deletes its [UnusedDeclaration.cut] instead.
const declaratorKinds = <SymbolKind>{.field, .variable, .constant};

/// A declaration to remove together with a reported one. It names its own
/// `filePath` (relative to the analyzed root, `/`-separated), so it can live in
/// another file, like a dead `StatefulWidget`'s `State` subclass.
///
/// `range`, `fullRange`, `kind` and `cut` mean what they do on
/// [UnusedDeclaration].
typedef CoupledRemoval = ({
  String filePath,
  SymbolKind kind,
  DeclarationRange range,
  DeclarationRange fullRange,
  DeclarationRange? cut,
});

/// The kind of a parameter that the body of its function never reads. The
/// server has no kind for a parameter, so ciach borrows the kind of a key,
/// which no Dart declaration is otherwise.
const parameterKind = SymbolKind.key;

/// Human-friendly labels for [SymbolKind], used in reports.
extension SymbolKindLabel on SymbolKind {
  /// A short, lower-case label (e.g. `class`, `enum value`).
  String get label => switch (this) {
    .class$ => 'class',
    .enum$ => 'enum',
    // The server has no kind for a mixin and tags it as a class; ciach
    // reports it as an interface, which no Dart declaration is otherwise.
    .interface$ => 'mixin',
    .namespace => 'extension',
    .struct => 'extension type',
    .operator$ => 'operator',
    .null$ => 'null',
    .enumMember => 'enum value',
    .typeParameter => 'type parameter',
    parameterKind => 'parameter',
    _ => name,
  };
}

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
    this.isEnumValue = false,
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
  /// type that declares it starts with `_`.
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
  final bool isEnumValue;

  /// Extra spans — each in a named file — that must be removed together with
  /// this declaration to keep the source compiling, but that are not
  /// themselves reported as findings.
  ///
  /// For example:
  ///
  /// - a dead `StatefulWidget`'s paired private `State<Widget>` subclass, which
  ///   is not independently "unused" (the widget's own `createState` references
  ///   it) yet becomes uncompilable the moment the widget is deleted
  ///   (`State<DeletedWidget>` no longer resolves).
  /// - every override of a dead member, which `skipOverrides` keeps out of the
  ///   findings and which would be left overriding nothing.
  /// - each `with` or `implements` clause entry that names a removed class or
  ///   mixin.
  ///
  /// Coupling a removal keeps `--remove` from breaking the build without
  /// surfacing the coupled span as a separate report entry.
  final List<CoupledRemoval> coupledRemovals;

  /// Whether this finding is real (the declaration is dead) but `--remove`
  /// must *not* delete it automatically, because doing so safely would require
  /// a source rewrite this tool won't attempt.
  ///
  /// Set for every dead sealed member surfaced by `--also union-members` (a
  /// class that is only ever *matched* by a type pattern, never constructed):
  /// deleting it would mean removing the member and rewriting every now-non-
  /// exhaustive `switch`/`if`-`case` over its supertype. Also set for a member
  /// whose override this tool won't delete — one in an unscanned file, or a
  /// declaring parameter — which would be left overriding nothing. The declaration is still
  /// reported so a human can act on it; it — and anything coupled to it — is
  /// simply skipped by the remover.
  final bool removalBlocked;

  /// An optional advisory note shown alongside the finding — extra context that
  /// doesn't change whether or how it is removed. Set for a sole, zero-parameter
  /// private constructor (`Foo._();`): it is reported and removable like any
  /// other dead code, but the note nudges toward `abstract final class` as the
  /// idiomatic way to make a static-only class non-instantiable.
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
    isEnumValue: isEnumValue,
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
