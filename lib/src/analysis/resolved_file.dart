/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/declaration_annotation.dart';
import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/source/semantic_tokens.dart';

/// A file as the analyzer resolves it: its declarations, and what the
/// entry-point rules read about their annotations and classes.
final class ResolvedFile {
  const ResolvedFile({
    required this.outline,
    required this.tokens,
    required this.annotations,
    required this.supertypes,
    required this.needSuperArguments,
    required this.firstError,
  });

  /// The outline of the whole file.
  final Outline outline;

  /// The tokens of the file, in order.
  final List<SemanticToken> tokens;

  /// The annotations of each declaration that has any, by the start of its
  /// name. A variable has the annotations of its statement.
  final Map<Position, List<DeclarationAnnotation>> annotations;

  /// All the supertypes of each class and mixin, by the position of its name.
  final Map<Position, Set<ResolvedClass>> supertypes;

  /// The names of the classes whose superclass has no unnamed constructor
  /// that takes no arguments, by position. An implicit default constructor
  /// of such a class, which calls `super()`, wouldn't compile.
  final Set<Position> needSuperArguments;

  /// The first compile error in the file, or `null` when it has none.
  final ({Position position, String message})? firstError;
}
