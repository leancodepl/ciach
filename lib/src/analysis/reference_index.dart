/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:ciach/src/analysis/element_uses.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';

/// A declaration as every analysis context names it: the path of the file
/// that declares it, the offset of its first fragment, its kind, which tells
/// a field from its getter and setter, and its name, which tells apart the
/// fields that one primary constructor declares, since their fragments share
/// an offset.
///
/// Each analysis context, one per package, builds elements of its own, so
/// the class `Foo` that another package imports is not the same object as
/// the class `Foo` that its own package declares.
typedef _Declaration = ({
  String path,
  int offset,
  ElementKind kind,
  String? name,
});

/// The uses of declarations in the files that were added, and the references
/// of a declaration as the analysis server's `textDocument/references`
/// reports them.
final class ReferenceIndex {
  /// The uses of each declaration.
  final _uses = <_Declaration, List<Location>>{};

  /// The types that name each type in their `extends`, `with`, `on` or
  /// `implements` clause.
  final _directSubtypes = <_Declaration, Map<_Declaration, InterfaceElement>>{};

  /// Adds the uses in [unit], the file at [path] whose lines [lineInfo] holds,
  /// and the supertypes of the types that it declares.
  void add(String path, CompilationUnit unit, LineInfo lineInfo) {
    final uri = Uri.file(path).toString();
    for (final (:element, :offset, :length) in elementUses(unit)) {
      if (_declarationOf(element) case final declaration?) {
        (_uses[declaration] ??= []).add(
          .new(
            uri: uri,
            range: .new(
              start: lineInfo.positionOf(offset),
              end: lineInfo.positionOf(offset + length),
            ),
          ),
        );
      }
    }
    for (final declaration in unit.declarations) {
      if ((
            declaration.declaredFragment?.element,
            declaration.declaredFragment?.element.let(_declarationOf),
          )
          case (final InterfaceElement type, final subtype?)) {
        for (final supertype in _namedSupertypes(declaration)) {
          if (_declarationOf(supertype) case final key?) {
            (_directSubtypes[key] ??= {})[subtype] = type;
          }
        }
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
      MethodElement() || FieldElement() => _hierarchyOf(element),
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
          ...?_declarationOf(declared)?.let((key) => _uses[key]),
    }.sorted(_byPlace);
  }

  /// The members that the analysis server searches for the references of
  /// the instance [member]: the methods and fields named like it in the types
  /// above its type that declare such a member, and in all the subtypes of
  /// those types. A private member is searched for only in its own library,
  /// and a field also by its `this.` parameters.
  Iterable<Element> _hierarchyOf(Element member) {
    if (member
        case FieldElement(isStatic: true) || MethodElement(isStatic: true)) {
      return [member];
    }
    final type = member.enclosingElement;
    if (type is! InterfaceElement) {
      return [member];
    }
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
              ?_declarationOf(declaring): declaring,
              ..._allSubtypes(declaring),
            },
        }..removeWhere(
          (_, type) => member.isPrivate && _libraryPathOf(type) != library,
        );
    final field = _declarationOf(member);
    return [
      for (final type in types.values) ...[
        ...type.fields.where((field) => field.lookupName == name),
        ...type.methods.where((method) => method.lookupName == name),
        if (member is FieldElement)
          for (final constructor in type.constructors)
            for (final parameter in constructor.formalParameters)
              if (parameter case FieldFormalParameterElement(
                field: final parameterField?,
              ) when _declarationOf(parameterField) == field)
                parameter,
      ],
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

  /// The types that extend, mix in or implement [type], directly or through
  /// other types, among the types of the added files.
  Map<_Declaration, InterfaceElement> _allSubtypes(InterfaceElement type) {
    final subtypes = <_Declaration, InterfaceElement>{};
    void addSubtypesOf(_Declaration type) {
      if (_directSubtypes[type] case final direct?) {
        for (final MapEntry(key: subtype, value: element) in direct.entries) {
          if (!subtypes.containsKey(subtype)) {
            subtypes[subtype] = element;
            addSubtypesOf(subtype);
          }
        }
      }
    }

    if (_declarationOf(type) case final declaration?) {
      addSubtypesOf(declaration);
    }
    return subtypes;
  }

  /// The declaration of [element], or `null` for an element that no file
  /// declares, such as `dynamic`.
  static _Declaration? _declarationOf(Element element) {
    final fragment = element.firstFragment;
    return fragment.libraryFragment?.source.fullName.let(
      (path) => (
        path: path,
        offset: fragment.offset,
        kind: element.kind,
        name: element.name,
      ),
    );
  }

  /// The path of the library that declares [element].
  static String? _libraryPathOf(Element element) =>
      element.library?.firstFragment.source.fullName;

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

  static int _byPlace(Location a, Location b) => switch ((
    a.uri.compareTo(b.uri),
    a.range.start.line.compareTo(b.range.start.line),
  )) {
    (0, 0) => a.range.start.character.compareTo(b.range.start.character),
    (0, final byLine) => byLine,
    (final byFile, _) => byFile,
  };
}
