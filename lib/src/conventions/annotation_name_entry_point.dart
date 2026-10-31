/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by the name written in an annotation on
/// it, such as `JSExport` in `@JSExport()` and `reflectiveTest` in
/// `@reflectiveTest`, whatever it resolves to, and optionally by the string
/// literal that the annotation's first argument is. It needs no requests to
/// the analysis server.
final class AnnotationNameEntryPoint extends EntryPoint {
  AnnotationNameEntryPoint(
    this.annotation, {
    this.argument,
    this.reason,
    this.members,
    super.files = const [],
  }) : super._();

  /// The name written after the `@`.
  final String annotation;

  /// The value of the string literal that the annotation's first argument
  /// has to be, such as `vm:entry-point` in `@pragma('vm:entry-point')`, or
  /// `null` for any arguments.
  final String? argument;

  @override
  final String? reason;

  @override
  final KeptMembers? members;

  @override
  bool _selects(ResolvedDeclaration declaration) {
    final tokens = declaration.leadingMetadata.toList();
    // The server gives the `(` of an annotation a token, so the first
    // argument is the second token after the name.
    return tokens.indexed.any(
      (named) =>
          named.$2.isAnnotationNamed(annotation) &&
          (argument == null ||
              (tokens.elementAtOrNull(named.$1 + 1)?.text == '(' &&
                  tokens.elementAtOrNull(named.$1 + 2)?.stringValue ==
                      argument)),
    );
  }

  @override
  AnnotationNameEntryPoint _withFiles(List<String> files) => .new(
    annotation,
    argument: argument,
    reason: reason,
    members: members,
    files: files,
  );

  @override
  String get label => [
    'declarations annotated with `@$annotation`',
    if (argument case final argument?) "with `'$argument'`",
  ].join(' ');
}
