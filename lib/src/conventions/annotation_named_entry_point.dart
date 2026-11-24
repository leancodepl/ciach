/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by an annotation on it: by the name
/// written after the `@`, such as `JSExport` in `@JSExport()` and
/// `reflectiveTest` in `@reflectiveTest`, or, with [matchesClass], by the
/// class of the object that the annotation creates, or a supertype of it,
/// which the analysis server finds. It optionally also checks the package
/// that declares the annotation and the string literal that its first
/// argument is.
final class AnnotationNamedEntryPoint extends EntryPoint {
  AnnotationNamedEntryPoint(
    this.annotation, {
    required this.packages,
    this.matchesClass = false,
    this.argument,
    this.reason,
    this.members,
    super.files = const [],
  }) : assert(
         argument == null || !matchesClass,
         'The argument is checked only without `matchesClass`.',
       ),
       super._();

  /// The name written after the `@`, or with [matchesClass], the name of the
  /// class.
  final String annotation;

  /// The packages that may declare [annotation]: a package name, such as
  /// `test_reflective_loader`, or an SDK library, such as `dart:core`.
  final Set<String> packages;

  /// Whether the rule asks the analysis server for the class of the object
  /// that the annotation creates, instead of comparing the name written after
  /// the `@`. A rule for `Preview` then also matches `@DarkPreview()` for a
  /// subclass, `@PreviewAlias()` for a typedef and `@preview` for
  /// `const preview = Preview();`, whose names differ from `Preview`.
  final bool matchesClass;

  /// The value of the string literal that the annotation's first argument
  /// has to be, such as `vm:entry-point` in `@pragma('vm:entry-point')`, or
  /// `null` for any arguments.
  final String? argument;

  @override
  final String? reason;

  @override
  final KeptMembers? members;

  @override
  Set<String> get annotationNames => matchesClass ? const {} : {annotation};

  @override
  Set<ServerLookup> get lookups => {if (matchesClass) .annotationClasses};

  @override
  bool _selects(ResolvedDeclaration declaration) => matchesClass
      ? declaration.annotationClasses.any(
          (it) => _isAnnotation(it.type) || it.supertypes.any(_isAnnotation),
        )
      : _annotatesByName(declaration);

  bool _isAnnotation(ResolvedClass type) =>
      type.name == annotation && packages.contains(type.package);

  bool _annotatesByName(ResolvedDeclaration declaration) {
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
  AnnotationNamedEntryPoint _withFiles(List<String> files) => .new(
    annotation,
    packages: packages,
    matchesClass: matchesClass,
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
    if (matchesClass) 'or a subtype of it',
    if (argument case final argument?) "with `'$argument'`",
  ].join(' ');
}
