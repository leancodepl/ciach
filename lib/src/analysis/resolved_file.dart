/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/declaration_annotation.dart';
import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/source/ignore_markers.dart';
import 'package:ciach/src/source/line_starts.dart';
import 'package:ciach/src/source/outline.dart';

/// A file as the analyzer resolves it: its declarations, and what the
/// entry-point rules read about their annotations and classes.
final class ResolvedFile {
  const ResolvedFile({
    required this.content,
    required this.lineStarts,
    required this.markers,
    required this.outline,
    required this.annotations,
    required this.supertypes,
    required this.needSuperArguments,
    required this.firstError,
  });

  /// The text of the file.
  final String content;

  /// The offset at which each line of [content] starts.
  final List<int> lineStarts;

  /// The `// ciach:` markers in the file.
  final IgnoreMarkers markers;

  /// The outline of the whole file.
  final Outline outline;

  /// The annotations of each declaration that has any, by the offset of its
  /// name. A variable has the annotations of its statement.
  final Map<int, List<DeclarationAnnotation>> annotations;

  /// All the supertypes of each class and mixin, by the offset of its name.
  final Map<int, Set<ResolvedClass>> supertypes;

  /// The offsets of the names of the classes whose superclass has no unnamed
  /// constructor that takes no arguments. An implicit default constructor of
  /// such a class, which calls `super()`, wouldn't compile.
  final Set<int> needSuperArguments;

  /// The first compile error in the file, or `null` when it has none.
  final ({int offset, String message})? firstError;

  /// The zero-based line and column of [offset].
  ({int line, int column}) positionOf(int offset) =>
      positionIn(lineStarts, offset);
}
