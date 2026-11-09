/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// The `import`, `export` and `part` directives of Dart source, read with the
/// analyzer's parser. These functions take text rather than a resolved file,
/// so that they also read a file that `--remove` has just edited.
library;

import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/analysis/utilities.dart';
import 'package:analyzer/dart/ast/ast.dart' hide Directive;
import 'package:ciach/src/workspace/packages.dart';

/// The keyword that starts a [Directive].
enum DirectiveKind { import, export, part, partOf }

/// An `import`, `export`, `part` or `part of` directive.
final class Directive {
  const Directive({
    required this.kind,
    required this.uris,
    required this.isConditional,
    required this.start,
    required this.end,
    this.shown,
    this.hidden = const {},
  });

  final DirectiveKind kind;

  /// The URIs it names, the default one first: `['io.dart', 'web.dart']` for
  /// `import 'io.dart' if (dart.library.js_interop) 'web.dart';`.
  final List<String> uris;

  /// Whether it has an `if (…)` clause.
  final bool isConditional;

  /// The offset of its first character, which is that of its doc comment or
  /// annotation when it has one.
  final int start;

  /// The offset just past its `;`.
  final int end;

  /// The names that its `show` clauses let through, or `null` when it has
  /// none.
  final Set<String>? shown;

  /// The names that its `hide` clauses leave out.
  final Set<String> hidden;

  /// The files it names, written in [from], as absolute paths. URIs of other
  /// schemes and unknown packages are left out.
  List<String> pathsFrom(String from, PackageResolver packages) => [
    for (final uri in uris)
      if (packages.resolve(uri, from) case final path? && != unknownPackage)
        path,
  ];
}

/// The `import`, `export`, `part` and `part of` directives of [content], in
/// order.
List<Directive> directivesIn(String content) => [
  for (final directive in _parse(content).unit.directives)
    ?switch (directive) {
      ImportDirective() => _namespaceDirective(.import, directive),
      ExportDirective() => _namespaceDirective(.export, directive),
      PartDirective(:final uri) => .new(
        kind: .part,
        uris: [?uri.stringValue],
        isConditional: false,
        start: directive.offset,
        end: directive.end,
      ),
      PartOfDirective(:final uri) => .new(
        kind: .partOf,
        uris: [?uri?.stringValue],
        isConditional: false,
        start: directive.offset,
        end: directive.end,
      ),
      _ => null,
    },
];

/// Whether [content] has nothing but comments and `library`, `import` or
/// `part of` directives. An `export` or `part` directive counts as content:
/// the file passes something on. So does source that doesn't parse.
bool isDirectiveOnly(String content) {
  final result = _parse(content);
  return result.errors.isEmpty &&
      result.unit.declarations.isEmpty &&
      result.unit.directives.every(
        (directive) => switch (directive) {
          LibraryDirective() || ImportDirective() || PartOfDirective() => true,
          _ => false,
        },
      );
}

ParseStringResult _parse(String content) =>
    parseString(content: content, throwIfDiagnostics: false);

Directive _namespaceDirective(
  DirectiveKind kind,
  NamespaceDirective directive,
) {
  final combinators = directive.combinators;
  Set<String> names(Iterable<SimpleIdentifier> identifiers) => {
    for (final identifier in identifiers) identifier.name,
  };
  final shown = combinators
      .whereType<ShowCombinator>()
      .map((show) => names(show.shownNames))
      .toList();
  return .new(
    kind: kind,
    uris: [
      ?directive.uri.stringValue,
      for (final configuration in directive.configurations)
        ?configuration.uri.stringValue,
    ],
    isConditional: directive.configurations.isNotEmpty,
    start: directive.offset,
    end: directive.end,
    shown: shown.isEmpty ? null : shown.reduce((a, b) => a.intersection(b)),
    hidden: {
      for (final hide in combinators.whereType<HideCombinator>())
        ...names(hide.hiddenNames),
    },
  );
}
