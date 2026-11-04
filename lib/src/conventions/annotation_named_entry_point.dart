/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

part of 'entry_points.dart';

/// A rule that selects a declaration by an annotation on it: by the name
/// written after the `@`, such as `JSExport` in `@JSExport()` and
/// `reflectiveTest` in `@reflectiveTest`, or, with [subtypes] or
/// [constants], by the class of the object that the annotation creates or
/// one of its supertypes. It optionally also checks the package that declares
/// the annotation and the string literal that its first argument is.
final class AnnotationNamedEntryPoint extends EntryPoint {
  AnnotationNamedEntryPoint(
    this.annotation, {
    this.packages,
    this.subtypes = false,
    this.constants = false,
    this.argument,
    this.reason,
    this.members,
    super.files = const [],
  }) : assert(
         argument == null || !(subtypes || constants),
         'The argument is checked only without `subtypes` and `constants`.',
       ),
       super._();

  /// The name written after the `@`, or with [subtypes] or [constants], the
  /// name of the class.
  final String annotation;

  /// The packages that may declare [annotation]: a package name, such as
  /// `test_reflective_loader`, or an SDK library, such as `dart:core`; `null`
  /// for any package.
  final Set<String>? packages;

  /// Whether the rule selects a declaration by the class that the
  /// annotation's constructor call creates, which [annotation] or a subtype
  /// of it can be, as `@DarkPreview()` is for `Preview`, also through a
  /// typedef.
  final bool subtypes;

  /// Whether an annotation that reads a constant counts, such as `@story` for
  /// `const story = Story();`.
  final bool constants;

  /// Whether the rule reads the class of the object that the annotation
  /// creates, rather than the name after the `@`.
  bool get _readsClass => subtypes || constants;

  /// The value of the string literal that the annotation's first argument
  /// has to be, such as `vm:entry-point` in `@pragma('vm:entry-point')`, or
  /// `null` for any arguments.
  final String? argument;

  @override
  final String? reason;

  @override
  final KeptMembers? members;

  @override
  Set<String> get annotationNames =>
      _readsClass || packages == null ? const {} : {annotation};

  @override
  Set<ServerLookup> get lookups => {
    if (_readsClass) .annotationClasses,
    if (constants) .constantClasses,
  };

  @override
  bool _selects(ResolvedDeclaration declaration) => _readsClass
      ? declaration.annotationClasses.any(
          (it) =>
              (constants || !it.readsConstant) &&
              (_isAnnotation(it.type) ||
                  (subtypes && it.supertypes.any(_isAnnotation))),
        )
      : _annotatesByName(declaration);

  bool _isAnnotation(ResolvedClass type) =>
      type.name == annotation && _isFromPackages(type.package);

  bool _isFromPackages(String? package) => packages?.contains(package) ?? true;

  bool _annotatesByName(ResolvedDeclaration declaration) {
    final tokens = declaration.leadingMetadata.toList();
    // The server gives the `(` of an annotation a token, so the first
    // argument is the second token after the name.
    return tokens.indexed.any(
      (named) =>
          named.$2.isAnnotationNamed(annotation) &&
          _isFromPackages(declaration.annotationPackages[named.$2.start]) &&
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
    subtypes: subtypes,
    constants: constants,
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
    if (packages case final packages?)
      'from ${packages.map(_libraryOf).join(' or ')}',
    if (subtypes) 'or a subtype of it',
    if (_readsClass && !constants) 'by a constructor call',
    if (argument case final argument?) "with `'$argument'`",
  ].join(' ');
}
