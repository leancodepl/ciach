/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// A class as the analyzer resolves it.
final class ResolvedClass {
  const ResolvedClass(this.name, this.package);

  /// The name of the class, without type parameters.
  final String name;

  /// The package that declares the class, such as `flutter`, or the SDK
  /// library, such as `dart:core`. `null` for a class in a file outside every
  /// package.
  final String? package;

  /// Whether this is the class [name] from [package], or from any package
  /// when [package] is `null`.
  bool isNamed(String name, {String? package}) =>
      this.name == name && (package == null || this.package == package);

  @override
  bool operator ==(Object other) =>
      other is ResolvedClass && other.name == name && other.package == package;

  @override
  int get hashCode => Object.hash(name, package);

  @override
  String toString() => package?.let((package) => '$package $name') ?? name;
}

/// The class that an annotation's constructor call creates, with its
/// supertypes: `Preview` for `@Preview()`.
final class AnnotationClass {
  const AnnotationClass(this.type, this.supertypes);

  /// The class that the constructor creates.
  final ResolvedClass type;

  /// All the supertypes of [type].
  final Set<ResolvedClass> supertypes;

  static const _supertypesEquality = SetEquality<ResolvedClass>();

  @override
  bool operator ==(Object other) =>
      other is AnnotationClass &&
      other.type == type &&
      _supertypesEquality.equals(other.supertypes, supertypes);

  @override
  int get hashCode => Object.hash(type, _supertypesEquality.hash(supertypes));

  @override
  String toString() => '$type, supertypes $supertypes';
}
