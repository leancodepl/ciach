/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Builds the outline of a resolved file: its declarations, the members of
/// each type, and the local functions and the `test(...)` and `group(...)`
/// calls in each body.
///
/// It follows `DartUnitOutlineComputer` in the analysis server, except that
/// it gives a return type only to functions and methods, names a test or
/// group call after the function that it calls, and lists no Flutter
/// widgets: ciach reads none of these. Like the server's, it lists the
/// primary constructor of a class only, not of an enum or an extension type,
/// and gives an enum no type parameters.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:ciach/src/analysis/analyzer_versions.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/util/extensions.dart';

/// Returns the outline of [unit], and the element and the annotations of each
/// declaration in it, by the start of the declaration's name. A field that a
/// primary constructor declares is declared by its parameter, and a variable
/// has the annotations of its statement.
({
  Outline outline,
  Map<Position, Element> elements,
  Map<Position, List<Annotation>> annotations,
})
unitOutline(CompilationUnit unit) {
  final builder = _OutlineBuilder(unit.lineInfo);
  return (
    outline: builder._unit(unit),
    elements: builder._elements,
    annotations: builder._annotations,
  );
}

final class _OutlineBuilder {
  _OutlineBuilder(this._lineInfo);

  final LineInfo _lineInfo;
  final _elements = <Position, Element>{};
  final _annotations = <Position, List<Annotation>>{};

  Outline _unit(CompilationUnit unit) => _outline(
    unit,
    .new(kind: .compilationUnit, name: '<unit>', range: _rangeOf(unit)),
    [for (final member in unit.declarations) ..._declarations(member)],
  );

  /// The outlines of the declarations that [member] holds: one, or one per
  /// variable of a top-level variable declaration.
  List<Outline> _declarations(CompilationUnitMember member) => switch (member) {
    ClassDeclaration() => [_class(member)],
    MixinDeclaration(:final name, :final typeParameters, :final body) => [
      _type(member, .mixin, name, typeParameters, _members(body)),
    ],
    EnumDeclaration(:final namePart, :final body) => [
      _outline(
        member,
        .new(
          kind: .enum$,
          name: _nameOf(namePart.typeName),
          range: _rangeOf(namePart.typeName),
        ),
        [
          for (final constant in body.constants)
            _named(constant, .enumConstant, constant.name),
          ..._memberOutlines(body.members),
        ],
      ),
    ],
    ExtensionDeclaration() => [_extension(member)],
    ExtensionTypeDeclaration() => [_extensionType(member)],
    TopLevelVariableDeclaration(:final variables) => [
      for (final variable in variables.variables)
        _named(variable, .topLevelVariable, variable.name),
    ],
    FunctionDeclaration() => [_function(member)],
    ClassTypeAlias(:final name, :final typeParameters) => [
      _type(member, .classTypeAlias, name, typeParameters, const []),
    ],
    FunctionTypeAlias(:final name, :final parameters, :final typeParameters) =>
      [
        _outline(
          member,
          .new(
            kind: .functionTypeAlias,
            name: _nameOf(name),
            range: _rangeOf(name),
            parameters: parameters.toSource(),
            typeParameters: typeParameters?.toSource(),
          ),
        ),
      ],
    GenericTypeAlias(:final name, :final type, :final typeParameters) => [
      _outline(
        member,
        .new(
          kind: type is GenericFunctionType ? .functionTypeAlias : .typeAlias,
          name: _nameOf(name),
          range: _rangeOf(name),
          parameters: switch (type) {
            GenericFunctionType(:final parameters) => parameters.toSource(),
            _ => null,
          },
          typeParameters: typeParameters?.toSource(),
        ),
      ),
    ],
    _ => const [],
  };

  Outline _class(ClassDeclaration node) {
    final namePart = node.namePart;
    return _type(node, .class$, namePart.typeName, namePart.typeParameters, [
      ..._primaryConstructor(namePart),
      ..._members(node.body),
    ]);
  }

  Outline _extensionType(ExtensionTypeDeclaration node) {
    final namePart = extensionTypeNamePart(node);
    return _type(
      node,
      .extensionType,
      namePart.typeName,
      namePart.typeParameters,
      _members(node.body),
    );
  }

  /// The outline of the type [node] of [kind], named [name].
  Outline _type(
    AstNode node,
    OutlineKind kind,
    Token name,
    TypeParameterList? typeParameters,
    List<Outline> members,
  ) => _outline(
    node,
    .new(
      kind: kind,
      name: _nameOf(name),
      range: _rangeOf(name),
      typeParameters: typeParameters?.toSource(),
    ),
    members,
  );

  /// The outline of an extension. An unnamed one is named after its `on`
  /// type, and its name range is that type's.
  Outline _extension(ExtensionDeclaration node) {
    final extendedType = node.onClause?.extendedType;
    return _outline(
      node,
      .new(
        kind: .extension,
        name: switch ((node.name?.lexeme, extendedType?.toSource())) {
          (final name? && != '', _) => name,
          (_, final onType? && != '') => 'extension on $onType',
          _ => '<unnamed extension>',
        },
        range: (node.name ?? extendedType)?.let(_rangeOf),
        typeParameters: node.typeParameters?.toSource(),
      ),
      _members(node.body),
    );
  }

  /// The members of a class, mixin, extension or extension type with the
  /// body [body]. A body of `;`, which a class with a primary constructor can
  /// have, has none.
  List<Outline> _members(AstNode body) => switch (body) {
    BlockClassBody(:final members) => _memberOutlines(members),
    _ => const [],
  };

  List<Outline> _memberOutlines(List<ClassMember> members) => [
    for (final member in members)
      ...switch (member) {
        ConstructorDeclaration() => [_constructor(member)],
        FieldDeclaration(:final fields) => [
          for (final field in fields.variables)
            _named(field, .field, field.name),
        ],
        MethodDeclaration() => [_method(member)],
        PrimaryConstructorBody(:final thisKeyword, :final body) => [
          _outline(
            member,
            .new(
              kind: .constructor,
              name: 'this',
              range: _rangeOf(thisKeyword),
            ),
            _bodyOutlines(body),
          ),
        ],
      },
  ];

  /// The primary constructor in the class header [namePart], if it has one,
  /// and the fields that its declaring parameters declare.
  List<Outline> _primaryConstructor(
    ClassNamePart namePart,
  ) => switch (namePart) {
    PrimaryConstructorDeclaration(
      declaredFragment: _?,
      :final typeName,
      :final constructorName,
      :final formalParameters,
    ) =>
      [
        _outline(
          namePart,
          .new(
            kind: .constructor,
            name: [typeName.lexeme, ?constructorName?.name.lexeme].join('.'),
            // A named one is named from its `.`, as the analysis server does.
            range: _rangeOf(constructorName ?? typeName),
            parameters: formalParameters.toSource(),
          ),
        ),
        for (final parameter in formalParameters.parameters)
          if (parameter case FormalParameter(
            declaredFragment: FormalParameterFragment(
              element: FieldFormalParameterElement(isDeclaring: true),
            ),
            :final name?,
          ))
            _named(parameter, .field, name),
      ],
    _ => const [],
  };

  /// The outline of a constructor, named like `Foo` or `Foo.named`. One
  /// declared with `new` or `factory` and no class name, such as
  /// `new named()`, is named with its class, and its name range is the
  /// keyword's when it has no name.
  Outline _constructor(ConstructorDeclaration node) {
    final typeName = node.typeName;
    final className =
        typeName?.name ??
        node.declaredFragment?.element.enclosingElement.name ??
        '<unknown>';
    final keyword = node.newKeyword ?? node.factoryKeyword;
    return _outline(
      node,
      .new(
        kind: .constructor,
        name: [
          className,
          // `new` names the unnamed constructor.
          if (node.name?.lexeme case final name? && != 'new') name,
        ].join('.'),
        range: _rangeOf(node.name ?? typeName ?? keyword ?? node),
        parameters: node.parameters.toSource(),
      ),
      _bodyOutlines(node.body),
    );
  }

  Outline _method(MethodDeclaration node) => _outline(
    node,
    .new(
      kind: _accessorOr(
        .method,
        isGetter: node.isGetter,
        isSetter: node.isSetter,
      ),
      name: _nameOf(node.name),
      range: _rangeOf(node.name),
      parameters: node.parameters?.toSource(),
      returnType: node.returnType?.toSource() ?? '',
      typeParameters: node.typeParameters?.toSource(),
    ),
    _bodyOutlines(node.body),
  );

  Outline _function(FunctionDeclaration node) {
    final FunctionExpression(:parameters, :typeParameters, :body) =
        node.functionExpression;
    return _outline(
      node,
      .new(
        kind: _accessorOr(
          .function,
          isGetter: node.isGetter,
          isSetter: node.isSetter,
        ),
        name: _nameOf(node.name),
        range: _rangeOf(node.name),
        parameters: parameters?.toSource() ?? '',
        returnType: node.returnType?.toSource() ?? '',
        typeParameters: typeParameters?.toSource(),
      ),
      _bodyOutlines(body),
    );
  }

  /// The outline of [node], a declaration of [kind] with nothing but a name.
  Outline _named(AstNode node, OutlineKind kind, Token name) => _outline(
    node,
    .new(kind: kind, name: _nameOf(name), range: _rangeOf(name)),
  );

  /// The local functions and the test and group calls in [body].
  List<Outline> _bodyOutlines(FunctionBody? body) {
    final visitor = _BodyOutlines(this);
    body?.accept(visitor);
    return visitor.outlines;
  }

  /// The outline of [node] with [element] and [children]. The range of the
  /// first variable of a declaration starts with the declaration, its doc
  /// comment and annotations, and the range of the last ends with it.
  Outline _outline(
    AstNode node,
    OutlineElement element, [
    List<Outline> children = const [],
  ]) {
    final (start, end) = switch (node) {
      VariableDeclaration(
        parent: VariableDeclarationList(
          :final variables,
          parent: final statement?,
        ),
      ) =>
        (
          identical(variables.first, node) ? statement.offset : node.offset,
          identical(variables.last, node) ? statement.end : node.end,
        ),
      _ => (node.offset, node.end),
    };
    final codeStart = switch (node) {
      AnnotatedNode(:final firstTokenAfterCommentAndMetadata) =>
        firstTokenAfterCommentAndMetadata.offset,
      _ => node.offset,
    };
    if (element.range case final name?) {
      if (_declaredElementOf(node) case final declared?) {
        _elements[name.start] = declared;
      }
      if (_annotationsOf(node) case final annotations
          when annotations.isNotEmpty) {
        _annotations[name.start] = annotations;
      }
    }
    return .new(
      element: element,
      range: _lineInfo.rangeOf(start, end),
      codeRange: _lineInfo.rangeOf(codeStart, node.end),
      children: children,
    );
  }

  /// The element that [node] declares: the field of a declaring parameter,
  /// and the primary constructor of a primary constructor's body, whose
  /// `this` names it.
  static Element? _declaredElementOf(AstNode node) => switch (node) {
    FormalParameter(
      declaredFragment: FormalParameterFragment(
        element: FieldFormalParameterElement(:final field?),
      ),
    ) =>
      field,
    Declaration(:final declaredFragment?) => declaredFragment.element,
    PrimaryConstructorDeclaration(:final declaredFragment?) =>
      declaredFragment.element,
    // The body sits in the body of its type.
    PrimaryConstructorBody(parent: AstNode(:final parent)) =>
      _primaryConstructorOf(parent),
    _ => null,
  };

  /// The annotations of the declaration [node]. A variable has those of its
  /// statement.
  static List<Annotation> _annotationsOf(AstNode node) => switch (node) {
    VariableDeclaration(
      parent: VariableDeclarationList(parent: AnnotatedNode(:final metadata)),
    ) ||
    AnnotatedNode(:final metadata) ||
    FormalParameter(:final metadata) => metadata,
    _ => const [],
  };

  /// The primary constructor in the header of the class, enum or extension
  /// type [type], or `null` when it has none.
  static Element? _primaryConstructorOf(AstNode? type) {
    final namePart = switch (type) {
      ClassDeclaration(:final namePart) ||
      EnumDeclaration(:final namePart) => namePart,
      final ExtensionTypeDeclaration type => extensionTypeNamePart(type),
      _ => null,
    };
    return switch (namePart) {
      PrimaryConstructorDeclaration(:final declaredFragment?) =>
        declaredFragment.element,
      _ => null,
    };
  }

  /// The name of the declaration that [name] names. A name that error
  /// recovery made up is empty, and the analysis server shows it as
  /// `<unnamed>`.
  static String _nameOf(Token name) =>
      name.lexeme.isEmpty ? '<unnamed>' : name.lexeme;

  /// The kind of a getter or a setter, or else [kind].
  static OutlineKind _accessorOr(
    OutlineKind kind, {
    required bool isGetter,
    required bool isSetter,
  }) => switch ((isGetter, isSetter)) {
    (true, _) => .getter,
    (_, true) => .setter,
    _ => kind,
  };

  Range _rangeOf(SyntacticEntity entity) =>
      _lineInfo.rangeOf(entity.offset, entity.end);
}

/// Collects the outlines of the local functions in a body, and of the
/// `test(...)` and `group(...)` calls, with the outlines inside each group.
final class _BodyOutlines extends RecursiveAstVisitor<void> {
  _BodyOutlines(this._builder);

  final _OutlineBuilder _builder;
  final outlines = <Outline>[];

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) =>
      outlines.add(_builder._function(node));

  /// Adds a call of a test or group function. Like the analysis server, it
  /// skips the arguments of a call that resolves to no function or method,
  /// such as a call of a function that doesn't exist.
  @override
  void visitMethodInvocation(MethodInvocation node) {
    final name = node.methodName;
    final element = name.element;
    if (element is! ExecutableElement) {
      return;
    }
    if (_isGroup(element)) {
      final group = _BodyOutlines(_builder);
      node.argumentList.accept(group);
      outlines.add(_call(node, .unitTestGroup, group.outlines));
    } else if (_isTest(element)) {
      outlines.add(_call(node, .unitTestTest, const []));
    } else {
      super.visitMethodInvocation(node);
    }
  }

  /// The outline of the test or group call [node], named after the function
  /// that it calls.
  Outline _call(MethodInvocation node, OutlineKind kind, List<Outline> inside) {
    final range = _builder._rangeOf(node);
    return .new(
      element: .new(
        kind: kind,
        name: node.methodName.name,
        range: _builder._rangeOf(node.methodName),
      ),
      range: range,
      codeRange: range,
      children: inside,
    );
  }

  /// Whether [element] is annotated `@isTestGroup`, or is `group` from a
  /// library whose file name ends with `test.dart`.
  static bool _isGroup(ExecutableElement element) =>
      element.metadata.hasIsTestGroup || _isTestFunction(element, 'group');

  /// Whether [element] is annotated `@isTest`, or is `test` from a library
  /// whose file name ends with `test.dart`.
  static bool _isTest(ExecutableElement element) =>
      element.metadata.hasIsTest || _isTestFunction(element, 'test');

  static bool _isTestFunction(ExecutableElement element, String name) =>
      element is TopLevelFunctionElement &&
      element.name == name &&
      element.library.firstFragment.source.fullName.endsWith('test.dart');
}
