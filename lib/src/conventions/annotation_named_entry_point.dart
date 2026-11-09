/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by an annotation on it: by the name
/// written after the `@`, such as `JSExport` in `@JSExport()` and
/// `reflectiveTest` in `@reflectiveTest`, or, with [subtypes], by the class
/// that the annotation's constructor call creates or one of its supertypes.
/// It optionally also checks the package that declares the annotation and
/// the string literal that its first argument is.
final class AnnotationNamedEntryPoint extends EntryPoint {
  AnnotationNamedEntryPoint(
    this.annotation, {
    required this.packages,
    this.subtypes = false,
    this.argument,
    this.reason,
    this.members,
    super.files = const [],
  }) : assert(
         argument == null || !subtypes,
         'The argument is checked only without `subtypes`.',
       ),
       super._();

  /// The name written after the `@`, or with [subtypes], the name of the
  /// class.
  final String annotation;

  /// The packages that may declare [annotation]: a package name, such as
  /// `test_reflective_loader`, or an SDK library, such as `dart:core`.
  final Set<String> packages;

  /// Whether the rule selects a declaration by the class that the
  /// annotation's constructor call creates, which [annotation] or a subtype
  /// of it can be, as `@DarkPreview()` is for `Preview`, also through a
  /// typedef.
  final bool subtypes;

  /// The value of the string literal that the annotation's first argument
  /// has to be, such as `vm:entry-point` in `@pragma('vm:entry-point')`, or
  /// `null` for any arguments.
  final String? argument;

  @override
  final String? reason;

  @override
  final KeptMembers? members;

  @override
  bool _selects(ResolvedDeclaration declaration) => subtypes
      ? declaration.annotationClasses.any(
          (it) => _isAnnotation(it.type) || it.supertypes.any(_isAnnotation),
        )
      : _annotatesByName(declaration);

  bool _isAnnotation(ResolvedClass type) =>
      type.name == annotation && packages.contains(type.package);

  bool _annotatesByName(ResolvedDeclaration declaration) =>
      declaration.annotations.any(
        (it) =>
            it.name == annotation &&
            packages.contains(it.package) &&
            (argument == null || it.argument == argument),
      );

  @override
  AnnotationNamedEntryPoint _withFiles(List<String> files) => .new(
    annotation,
    packages: packages,
    subtypes: subtypes,
    argument: argument,
    reason: reason,
    members: members,
    files: files,
  );

  /// `package:flutter` for `flutter`, and `dart:core` as it is.
  static String _libraryOf(String package) =>
      package.startsWith('dart:') ? '`$package`' : '`package:$package`';

  @override
  String get label => [
    'declarations annotated with `@$annotation`',
    'from ${packages.map(_libraryOf).join(' or ')}',
    if (subtypes) 'or a subtype of it',
    if (argument case final argument?) "with `'$argument'`",
  ].join(' ');
}
