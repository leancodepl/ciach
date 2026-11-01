/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by the name written in an annotation on
/// it, such as `JSExport` in `@JSExport()` and `reflectiveTest` in
/// `@reflectiveTest`, and by the package that declares what the name refers
/// to. It optionally also checks the string literal that the annotation's
/// first argument is.
final class AnnotationNameEntryPoint extends EntryPoint {
  AnnotationNameEntryPoint(
    this.annotation, {
    required this.packages,
    this.argument,
    this.reason,
    this.members,
    super.files = const [],
  }) : super._();

  /// The name written after the `@`.
  final String annotation;

  /// The packages that may declare [annotation]: a package name, such as
  /// `test_reflective_loader`, or an SDK library, such as `dart:core`.
  final Set<String> packages;

  /// The value of the string literal that the annotation's first argument
  /// has to be, such as `vm:entry-point` in `@pragma('vm:entry-point')`, or
  /// `null` for any arguments.
  final String? argument;

  @override
  final String? reason;

  @override
  final KeptMembers? members;

  @override
  Set<String> get annotationNames => {annotation};

  @override
  bool _selects(ResolvedDeclaration declaration) {
    final tokens = declaration.leadingMetadata.toList();
    // The server gives the `(` of an annotation a token, so the first
    // argument is the second token after the name.
    return tokens.indexed.any(
      (named) =>
          named.$2.isAnnotationNamed(annotation) &&
          packages.contains(declaration.annotationPackages[named.$2.start]) &&
          (argument == null ||
              (tokens.elementAtOrNull(named.$1 + 1)?.text == '(' &&
                  tokens.elementAtOrNull(named.$1 + 2)?.stringValue ==
                      argument)),
    );
  }

  @override
  AnnotationNameEntryPoint _withFiles(List<String> files) => .new(
    annotation,
    packages: packages,
    argument: argument,
    reason: reason,
    members: members,
    files: files,
  );

  @override
  String get label => [
    'declarations annotated with `@$annotation`',
    'from ${packages.map((package) => '`$package`').join(' or ')}',
    if (argument case final argument?) "with `'$argument'`",
  ].join(' ');
}
