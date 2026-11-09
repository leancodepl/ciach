/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/analysis/element_declaration.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/reachability.dart';
import 'package:collection/collection.dart';

/// The subtypes of the types in the files that were added, and the members
/// of those subtypes that override a member.
final class TypeHierarchy {
  /// The types that name each type in their `extends`, `with`, `on` or
  /// `implements` clause.
  final _directSubtypes = <ElementDeclaration, Set<ElementDeclaration>>{};

  /// The element of each type that an added file declares.
  final _types = <ElementDeclaration, InterfaceElement>{};

  /// Adds the supertypes of the types that [unit] declares.
  void add(CompilationUnit unit) {
    for (final declaration in unit.declarations) {
      if (declaration.declaredFragment?.element
          case final InterfaceElement type) {
        if (ElementDeclaration.of(type) case final subtype?) {
          _types[subtype] = type;
          for (final supertype in _namedSupertypes(declaration)) {
            if (ElementDeclaration.of(supertype) case final key?) {
              (_directSubtypes[key] ??= {}).add(subtype);
            }
          }
        }
      }
    }
  }

  /// Returns the types that extend, mix in or implement [type], directly or
  /// through other types, among the types of the added files.
  Map<ElementDeclaration, InterfaceElement> subtypesOf(InterfaceElement type) =>
      {
        for (final subtype in reachableFrom(
          _directSubtypesOf(.of(type)),
          _directSubtypesOf,
        ))
          subtype: _types[subtype]!,
      };

  Iterable<ElementDeclaration> _directSubtypesOf(ElementDeclaration? type) => [
    ...?_directSubtypes[type],
  ];

  /// Returns the locations of the names of the members that override
  /// [member], sorted by file and position, as the analysis server's
  /// `textDocument/implementation` finds them: in each subtype of its type,
  /// the member that the subtype declares, or else the one that its last
  /// mixin that has one declares or inherits.
  ///
  /// A method is overridden by methods, a getter by getters and a setter by
  /// setters. A field is overridden by getters, and unless it is final, by
  /// setters in the types that have no getter of its name. Only the instance
  /// members of classes, mixins and enums have overrides.
  List<Location> overridesOf(Element member) => switch ((
    member,
    member.enclosingElement,
  )) {
    (
      ExecutableElement(isStatic: false) || FieldElement(isStatic: false),
      final InterfaceElement type,
    ) =>
      {
        for (final subtype in subtypesOf(type).values)
          if (_overrideIn(subtype, member)?.nonSynthetic case final override?)
            ?_nameOf(override),
      }.sorted(Location.byPlace),
    _ => const [],
  };

  /// The member of [type] that overrides [member]: the member that [type]
  /// declares, or else the one that the last mixin of [type] that has one
  /// declares or inherits, unless that is [member] itself.
  static ExecutableElement? _overrideIn(InterfaceElement type, Element member) {
    // An extension type redeclares the members of the types that it
    // implements, and only an extension type implements an extension type.
    if (type case ExtensionTypeElement()) {
      return null;
    }
    final (name, library) = (member.name, member.library);
    if (name == null || library == null) {
      return null;
    }
    // The member of the kind of [member] that the lookups find by its name.
    ExecutableElement? memberLike(
      MethodElement? Function(String) method,
      GetterElement? Function(String) getter,
      SetterElement? Function(String) setter,
    ) => switch (member) {
      MethodElement() => method(name),
      GetterElement() => getter(name),
      SetterElement() => setter(name),
      FieldElement(:final isFinal) =>
        getter(name) ?? (isFinal ? null : setter(name)),
      _ => null,
    };
    final declared = memberLike(type.getMethod, type.getGetter, type.getSetter);
    if (declared != null && declared.isAccessibleIn(library)) {
      return declared;
    }
    final inherited = type.mixins.reversed
        .map(
          (mixin) => memberLike(
            (name) => mixin.element.lookUpMethod(name: name, library: library),
            (name) => mixin.element.lookUpGetter(name: name, library: library),
            (name) => mixin.element.lookUpSetter(name: name, library: library),
          ),
        )
        .nonNulls
        .firstOrNull;
    // The getter of a field is the field.
    return inherited?.nonSynthetic.let(ElementDeclaration.of) == .of(member)
        ? null
        : inherited;
  }

  /// The location of the name of [element].
  static Location? _nameOf(Element element) {
    final fragment = element.firstFragment;
    return switch ((
      fragment.libraryFragment,
      fragment.nameOffset,
      fragment.name,
    )) {
      (final file?, final offset?, final name?) => .new(
        path: file.source.fullName,
        range: .new(start: offset, end: offset + name.length),
      ),
      _ => null,
    };
  }

  /// The types that the `extends`, `with`, `on` and `implements` clauses of
  /// [declaration] name. A type alias in such a clause is left out, as the
  /// analyzer's index leaves it out.
  static Iterable<InterfaceElement> _namedSupertypes(
    CompilationUnitMember declaration,
  ) => switch (declaration) {
    ClassDeclaration(
      :final extendsClause,
      :final withClause,
      :final implementsClause,
    ) =>
      [
        ?extendsClause?.superclass,
        ...?withClause?.mixinTypes,
        ...?implementsClause?.interfaces,
      ],
    ClassTypeAlias(
      :final superclass,
      :final withClause,
      :final implementsClause,
    ) =>
      [superclass, ...withClause.mixinTypes, ...?implementsClause?.interfaces],
    MixinDeclaration(:final onClause, :final implementsClause) => [
      ...?onClause?.superclassConstraints,
      ...?implementsClause?.interfaces,
    ],
    EnumDeclaration(:final withClause, :final implementsClause) => [
      ...?withClause?.mixinTypes,
      ...?implementsClause?.interfaces,
    ],
    ExtensionTypeDeclaration(:final implementsClause) => [
      ...?implementsClause?.interfaces,
    ],
    _ => const <NamedType>[],
  }.map((type) => type.element).whereType<InterfaceElement>();
}
