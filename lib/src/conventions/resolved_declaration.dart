/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// What the entry-point rules read about a declaration: its name and place,
/// its annotations with the packages that declare them, and the class that it
/// extends.
library;

import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Position;

/// A declaration that the entry-point rules are checked against.
final class ResolvedDeclaration {
  const ResolvedDeclaration({
    required this.relativePath,
    required this.symbol,
    this.container,
    this.inEnum = false,
    this.leadingMetadata = const [],
    this.annotationPackages = const {},
    this.superclass,
  });

  /// The file of the declaration, POSIX and relative to the package root.
  final String relativePath;

  final DocumentSymbol symbol;

  /// The name of the type that declares [symbol], or `null` at the top level.
  final String? container;

  /// The name of the declaration as the report prints it, such as
  /// `Container.member`.
  String get qualifiedName => symbol.qualifiedName(container);

  /// Whether [container] is an enum.
  final bool inEnum;

  /// The tokens of the declaration's doc comment and annotations.
  final Iterable<SemanticToken> leadingMetadata;

  /// The package that declares each annotation in [leadingMetadata] that a
  /// rule names, by the position of the name after the `@`: `dart:core` for
  /// `pragma` in `@pragma('vm:entry-point')`.
  final Map<Position, String> annotationPackages;

  /// The class that the declaration extends, when it is a class with an
  /// `extends` clause.
  final String? superclass;
}
