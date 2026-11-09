/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// What the entry-point rules read about a declaration: its name and place,
/// and its annotations and supertypes as the analyzer resolves them.
library;

import 'package:ciach/src/analysis/declaration_annotation.dart';
import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/symbols.dart';

/// A declaration that the entry-point rules are checked against.
final class ResolvedDeclaration {
  const ResolvedDeclaration({
    required this.relativePath,
    required this.outline,
    this.container,
    this.inEnum = false,
    this.annotations = const [],
    this.supertypes = const {},
  });

  /// The file of the declaration, POSIX and relative to the package root.
  final String relativePath;

  final Outline outline;

  /// The name of the type that declares [outline], or `null` at the top
  /// level.
  final String? container;

  /// The name of the declaration as the report prints it, such as
  /// `Container.member`.
  String get qualifiedName => outline.element.qualifiedName(container);

  /// Whether [container] is an enum.
  final bool inEnum;

  /// The annotations of the declaration. A variable has the annotations of
  /// its statement.
  final List<DeclarationAnnotation> annotations;

  /// The classes that the constructor calls in [annotations] create.
  Iterable<AnnotationClass> get annotationClasses =>
      annotations.map((annotation) => annotation.createdClass).nonNulls;

  /// All the supertypes of the declaration when it is a class or a mixin,
  /// and none otherwise.
  final Set<ResolvedClass> supertypes;
}
