/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/source/document_symbol.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/semantic_tokens.dart';

/// A file as the analyzer resolves it: its declarations, and what the
/// entry-point rules read about its annotations and classes.
///
/// The annotations are keyed by the position of the name that follows the `@`
/// and the import prefix, such as `Preview` in `@prefix.Preview.named()`.
final class ResolvedFile {
  ResolvedFile({
    required this.outline,
    required this.tokens,
    this.annotationPackages = const {},
    this.annotationClasses = const {},
    this.supertypes = const {},
    this.needSuperArguments = const {},
    this.firstError,
  });

  /// The outline of the whole file.
  final Outline outline;

  /// The tokens of the file, in order.
  final List<SemanticToken> tokens;

  /// The declarations at the top level of the file, with the declarations
  /// inside them.
  late final List<DocumentSymbol> symbols = [
    for (final declaration in outline.children) .fromOutline(declaration),
  ];

  /// The package that declares each annotation: `dart:core` for `pragma` in
  /// `@pragma('vm:entry-point')`.
  final Map<Position, String> annotationPackages;

  /// The class that each annotation that calls a constructor creates.
  final Map<Position, AnnotationClass> annotationClasses;

  /// All the supertypes of each class and mixin, by the position of its name.
  final Map<Position, Set<ResolvedClass>> supertypes;

  /// The names of the classes whose superclass has no unnamed constructor
  /// that takes no arguments, by position. An implicit default constructor
  /// of such a class, which calls `super()`, wouldn't compile.
  final Set<Position> needSuperArguments;

  /// The first compile error in the file, or `null` when it has none.
  final ({Position position, String message})? firstError;
}
