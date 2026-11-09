/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/analysis/declaration_annotation.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';

/// `freezed` union conventions.
///
/// A `@freezed`/`@Freezed` union's redirecting-factory arms are constructed
/// only by the generated `fromJson`, never hand-called, so a reference search
/// sees them as unused. This tracks which classes carry the annotation (fed in
/// during candidate collection) and, given a union whose `fromJson` is used,
/// treats those arms as live rather than dead.
class FreezedUnions {
  /// Keys `(path, class name)` of classes annotated `@freezed`/`@Freezed`.
  final _annotatedClasses = <DeclKey>{};

  /// Records [declaration] as a freezed class if it is a type annotated with
  /// `@freezed` or `@Freezed`.
  void noteIfAnnotated(
    String path,
    Outline declaration,
    List<DeclarationAnnotation> annotations,
  ) {
    if (declaration.element.declaresMembers &&
        annotations.any(
          (annotation) =>
              annotation.name == 'freezed' || annotation.name == 'Freezed',
        )) {
      _annotatedClasses.add(.new(path, declaration.element.name));
    }
  }

  /// Indices into [candidates] of redirecting-factory arms of a `@freezed`/
  /// `@Freezed` union with a referenced `fromJson` — live serialization members
  /// that read as unused. Conservative: never-dispatched arms are kept too,
  /// being statically indistinguishable from live ones.
  Set<int> deserializationOnlyArms(
    List<Candidate> candidates,
    List<RefStatus> statuses,
  ) {
    final unionsWithUsedFromJson = {
      for (final (i, c) in candidates.indexed)
        if (c.containerKey case final key?
            when c.kind == .constructor &&
                statuses[i] == .used &&
                c.outline.element.declarationName(c.container) == 'fromJson')
          key,
    };
    return {
      for (final (i, c) in candidates.indexed)
        if (c.containerKey case final key?
            when statuses[i] == .unused &&
                c.kind == .constructor &&
                _annotatedClasses.contains(key) &&
                unionsWithUsedFromJson.contains(key) &&
                c.outline.element.isRedirectingFactory)
          i,
    };
  }
}
