/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/analysis/resolved_class.dart';

/// An annotation of a declaration, as the analyzer resolves it: `pragma` from
/// `dart:core` with the argument `vm:entry-point` for
/// `@pragma('vm:entry-point')`.
final class DeclarationAnnotation {
  const DeclarationAnnotation(
    this.name, {
    this.package,
    this.argument,
    this.createdClass,
  });

  /// The name that follows the `@` and its import prefix: `Preview` in
  /// `@prefix.Preview.named()` and in `@Preview.named()`.
  final String name;

  /// The package that declares the annotation, such as `flutter`, or the SDK
  /// library, such as `dart:core`. `null` when the analyzer can't resolve it,
  /// or for a file outside every package.
  final String? package;

  /// The value of the first argument when it is a string without
  /// interpolation: `vm:entry-point` in `@pragma('vm:entry-point')`.
  final String? argument;

  /// The class that the annotation's constructor call creates, or `null` for
  /// an annotation that names a constant, such as `@override`.
  final AnnotationClass? createdClass;

  @override
  bool operator ==(Object other) =>
      other is DeclarationAnnotation &&
      other.name == name &&
      other.package == package &&
      other.argument == argument &&
      other.createdClass == createdClass;

  @override
  int get hashCode => Object.hash(name, package, argument, createdClass);

  @override
  String toString() => [
    '@$name',
    if (package != null) 'from $package',
    if (argument != null) "('$argument')",
    if (createdClass != null) 'creating $createdClass',
  ].join(' ');
}
