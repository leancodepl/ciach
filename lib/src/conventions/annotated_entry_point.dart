/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by the class of an annotation on it.
final class AnnotatedEntryPoint extends EntryPoint {
  AnnotatedEntryPoint(
    this.annotation, {
    this.package,
    bool? subtypes,
    bool? constants,
    required this.reason,
    super.files = const [],
  }) : subtypes = subtypes ?? true,
       constants = constants ?? true,
       super._();

  @override
  final String reason;

  /// The class of the annotation.
  final String annotation;

  /// The package that declares [annotation], or `null` for any package.
  final String? package;

  /// Whether an annotation whose class is a subtype of [annotation] counts.
  final bool subtypes;

  /// Whether an annotation that reads a constant counts.
  final bool constants;

  @override
  Set<ServerLookup> get lookups => {
    .annotationClasses,
    if (constants) .constantClasses,
  };

  @override
  bool _selects(ResolvedDeclaration declaration) => declaration.annotations.any(
    (it) =>
        (constants || !it.readsConstant) &&
        (it.type.isNamed(annotation, package: package) ||
            (subtypes &&
                it.supertypes.any(
                  (type) => type.isNamed(annotation, package: package),
                ))),
  );

  @override
  AnnotatedEntryPoint _withFiles(List<String> files) => .new(
    annotation,
    package: package,
    subtypes: subtypes,
    constants: constants,
    reason: reason,
    files: files,
  );

  @override
  String get label => [
    'declarations annotated with `@$annotation`',
    if (package case final package?) 'from `package:$package`',
    if (subtypes) 'or a subtype of it',
    if (!constants) 'by a constructor call',
  ].join(' ');
}
