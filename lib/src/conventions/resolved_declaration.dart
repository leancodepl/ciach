/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// What the entry-point rules read about a declaration: its name and place,
/// the packages that declare its annotations, and the classes of its
/// annotations and supertypes as the analysis server resolves them.
library;

import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Position;

/// A class as the analysis server resolves it.
final class ResolvedClass {
  const ResolvedClass(this.name, this.package);

  /// The name of the class, without type parameters.
  final String name;

  /// The package that declares the class, such as `flutter`, or `null` for a
  /// class outside every package, such as `Object`.
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
  String toString() =>
      package?.let((package) => 'package:$package $name') ?? name;
}

/// The class of the object that an annotation creates, with its supertypes:
/// `Preview` for `@Preview()`, or for `@preview` with
/// `const preview = Preview();`.
final class AnnotationClass {
  const AnnotationClass(
    this.type,
    this.supertypes, {
    required this.readsConstant,
  });

  /// The class of the object.
  final ResolvedClass type;

  /// All the supertypes of [type].
  final Set<ResolvedClass> supertypes;

  /// Whether the annotation reads a constant, as `@preview` does, rather than
  /// calling a constructor.
  final bool readsConstant;

  static const _supertypesEquality = SetEquality<ResolvedClass>();

  @override
  bool operator ==(Object other) =>
      other is AnnotationClass &&
      other.type == type &&
      other.readsConstant == readsConstant &&
      _supertypesEquality.equals(other.supertypes, supertypes);

  @override
  int get hashCode =>
      Object.hash(type, readsConstant, _supertypesEquality.hash(supertypes));

  @override
  String toString() =>
      '${readsConstant ? 'constant ' : ''}$type, supertypes $supertypes';
}

/// A declaration that the entry-point rules are checked against.
final class ResolvedDeclaration {
  const ResolvedDeclaration({
    required this.relativePath,
    required this.symbol,
    this.container,
    this.inEnum = false,
    this.leadingMetadata = const [],
    this.annotationPackages = const {},
    this.annotationClasses = const [],
    this.supertypes = const {},
  });

  /// The file of the declaration, POSIX and relative to the package root.
  final String relativePath;

  final DocumentSymbol symbol;

  /// The name of the type that declares [symbol], or `null` at the top level.
  final String? container;

  /// The name of the declaration as the report prints it, such as
  /// `Container.member`.
  String get qualifiedName => symbol.qualifiedName(container);

  /// Whether [container] is an enum.
  final bool inEnum;

  /// The tokens of the declaration's doc comment and annotations.
  final Iterable<SemanticToken> leadingMetadata;

  /// The package that declares each annotation in [leadingMetadata] that a
  /// rule names, by the position of the name after the `@`: `dart:core` for
  /// `pragma` in `@pragma('vm:entry-point')`.
  final Map<Position, String> annotationPackages;

  /// The classes of the objects that the declaration's annotations create.
  final List<AnnotationClass> annotationClasses;

  /// All the supertypes of the declaration when it is a class, and none
  /// otherwise.
  final Set<ResolvedClass> supertypes;
}
