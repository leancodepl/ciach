/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// What the entry-point rules read about a declaration: its name and place,
/// the packages that declare its annotations, and the classes of its
/// annotations and supertypes as the analyzer resolves them.
library;

import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/semantic_tokens.dart';
import 'package:ciach/src/source/symbols.dart';

/// A declaration that the entry-point rules are checked against.
final class ResolvedDeclaration {
  const ResolvedDeclaration({
    required this.relativePath,
    required this.outline,
    this.container,
    this.inEnum = false,
    this.leadingMetadata = const [],
    this.annotationPackages = const {},
    this.annotationClasses = const [],
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

  /// The tokens of the declaration's doc comment and annotations.
  final Iterable<SemanticToken> leadingMetadata;

  /// The package that declares each annotation in [leadingMetadata], by the
  /// position of the name after the `@` and its import prefix: `dart:core`
  /// for `pragma` in `@pragma('vm:entry-point')`.
  final Map<Position, String> annotationPackages;

  /// The classes that the constructor calls in the declaration's
  /// annotations create.
  final List<AnnotationClass> annotationClasses;

  /// All the supertypes of the declaration when it is a class or a mixin,
  /// and none otherwise.
  final Set<ResolvedClass> supertypes;
}
