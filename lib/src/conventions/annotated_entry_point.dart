/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by the class that a constructor call in
/// an annotation on it creates.
final class AnnotatedEntryPoint extends EntryPoint {
  AnnotatedEntryPoint(
    this.annotation, {
    this.package,
    required this.reason,
    super.files = const [],
  }) : super._();

  @override
  final String reason;

  /// The class of the annotation.
  final String annotation;

  /// The package that declares [annotation], or `null` for any package.
  final String? package;

  @override
  Set<ServerLookup> get lookups => const {.annotationClasses};

  @override
  bool _selects(ResolvedDeclaration declaration) => declaration.annotations.any(
    (it) =>
        it.type.isNamed(annotation, package: package) ||
        it.supertypes.any((type) => type.isNamed(annotation, package: package)),
  );

  @override
  AnnotatedEntryPoint _withFiles(List<String> files) =>
      .new(annotation, package: package, reason: reason, files: files);

  @override
  String get label => [
    'declarations annotated with `@$annotation`',
    if (package case final package?) 'from `package:$package`',
    'or a subtype of it',
  ].join(' ');
}
