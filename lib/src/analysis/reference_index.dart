/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/analysis/element_declaration.dart';
import 'package:ciach/src/analysis/element_uses.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/analysis/type_hierarchy.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:collection/collection.dart';

/// The uses of declarations in the files that were added, and the references
/// of a declaration as the analysis server's `textDocument/references`
/// reports them.
final class ReferenceIndex {
  /// Creates an index whose instance members are referenced through the
  /// types of [_hierarchy].
  ReferenceIndex(this._hierarchy);

  final TypeHierarchy _hierarchy;

  /// The uses of each declaration.
  final _uses = <ElementDeclaration, List<Location>>{};

  /// Adds the uses in [unit], the file at [path].
  void add(String path, CompilationUnit unit) {
    for (final (:element, :offset, :length) in elementUses(unit)) {
      if (ElementDeclaration.of(element) case final declaration?) {
        (_uses[declaration] ??= []).add(
          unit.lineInfo.locationOf(path, offset, length),
        );
      }
    }
  }

  /// Returns the references of [declaration], sorted by file and position.
  ///
  /// They are the uses of [declaration], and for a variable or a field, also
  /// the uses of its getter and setter; a getter or a setter counts as its
  /// variable. An instance method or field is referenced by the uses of each
  /// method and field of the same name in the types that its type implements,
  /// and in their subtypes, and a field also by the arguments that its
  /// `this.` parameters receive by name.
  List<Location> referencesTo(Element declaration) {
    final element = switch (declaration.baseElement) {
      PropertyAccessorElement(:final variable) => variable,
      final element => element,
    };
    final searched = switch (element) {
      MethodElement(
        isStatic: false,
        enclosingElement: final InterfaceElement type,
      ) ||
      FieldElement(
        isStatic: false,
        enclosingElement: final InterfaceElement type,
      ) => _hierarchyOf(element, type),
      _ => [element],
    };
    return {
      for (final element in searched)
        for (final declared in [
          element,
          if (element case PropertyInducingElement(
            :final getter,
            :final setter,
          )) ...[
            ?getter,
            ?setter,
          ],
        ])
          ...?_uses[ElementDeclaration.of(declared)],
    }.sorted(Location.byPlace);
  }

  /// The members that the analysis server searches for the references of
  /// the instance [member] of [type]: the methods and fields named like it in
  /// the types above [type] that declare such a member, and in all the
  /// subtypes of those types. A private member is searched for only in its
  /// own library, and a field also by the `this.` parameters of [type].
  Iterable<Element> _hierarchyOf(Element member, InterfaceElement type) {
    final name = member.displayName;
    final library = _libraryPathOf(member);
    final types =
        {
          for (final declaring in [
            for (final supertype in type.allSupertypes)
              if (member.isPublic ||
                  _libraryPathOf(supertype.element) == library)
                supertype.element,
            type,
          ])
            if (_declaresMember(declaring, name)) ...{
              ?ElementDeclaration.of(declaring): declaring,
              ..._hierarchy.subtypesOf(declaring),
            },
        }..removeWhere(
          (_, type) => member.isPrivate && _libraryPathOf(type) != library,
        );
    return [
      for (final searchedType in types.values) ...[
        ...searchedType.fields.where((field) => field.lookupName == name),
        ...searchedType.methods.where((method) => method.lookupName == name),
      ],
      // A `this.` parameter names a field of its own class.
      if (member case FieldElement())
        for (final constructor in type.constructors)
          for (final parameter in constructor.formalParameters)
            if (parameter case FieldFormalParameterElement(
              :final field?,
            ) when ElementDeclaration.of(field) == .of(member))
              parameter,
    ];
  }

  /// Whether [type] declares a field, getter, setter or method that
  /// [name] names.
  static bool _declaresMember(InterfaceElement type, String name) => [
    ...type.fields,
    ...type.getters,
    ...type.setters,
    ...type.methods,
  ].any((member) => member.displayName == name);

  /// The path of the library that declares [element].
  static String? _libraryPathOf(Element element) =>
      element.library?.firstFragment.source.fullName;
}
