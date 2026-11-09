/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';

/// The outline of a declaration named [name]; its ranges are irrelevant to
/// the rules.
Outline declared(String name, {OutlineKind kind = .function}) {
  const range = Range(
    start: .new(line: 0, character: 0),
    end: .new(line: 0, character: 0),
  );
  return .new(
    element: .new(kind: kind, name: name, range: range),
    range: range,
    codeRange: range,
    children: const [],
  );
}

/// [outline] in the file at [path], inside [container].
ResolvedDeclaration declarationAt(
  String path,
  Outline outline,
  String? container, {
  bool inEnum = false,
  List<AnnotationClass> annotationClasses = const [],
}) => .new(
  relativePath: path,
  outline: outline,
  container: container,
  inEnum: inEnum,
  annotationClasses: annotationClasses,
);
