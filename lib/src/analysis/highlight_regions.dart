/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// The regions of a resolved file that name something, each typed as the
/// analysis server's `DartUnitHighlightsComputer` types it, which
/// `unitTokens` turns into tokens.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/analysis/analyzer_versions.dart';
import 'package:ciach/src/analysis/argument_names.dart';
import 'package:ciach/src/analysis/assignments.dart';

/// The text from [offset] to [offset] + [length] as one token of [type] with
/// [modifiers].
final class HighlightRegion {
  HighlightRegion(
    this.offset,
    this.length,
    this.type, [
    this.modifiers = const {},
  ]);

  HighlightRegion.of(
    SyntacticEntity entity,
    String type, [
    Set<String> modifiers = const {},
  ]) : this(entity.offset, entity.length, type, modifiers);

  final int offset;
  final int length;
  final String type;
  final Set<String> modifiers;

  int get end => offset + length;

  /// Orders regions by start, and a region before the regions inside it.
  static int byPlace(HighlightRegion a, HighlightRegion b) =>
      switch (a.offset.compareTo(b.offset)) {
        0 => b.length.compareTo(a.length),
        final byStart => byStart,
      };
}

/// Collects a region for each name in a file, typed after what it names, and
/// for the `@` and parentheses of each annotation.
final class HighlightRegions extends RecursiveAstVisitor<void> {
  final regions = <HighlightRegion>[];

  /// The offsets of the tokens that get no region of their own: the tokens
  /// that a region of [regions] covers after its first, such as `of` in
  /// `part of` and `*` in `sync*`, and the field names of record types.
  final covered = <int>{};

  void _add(Token? name, Element? element, {Set<String> modifiers = const {}}) {
    if (name != null && name.length > 0) {
      regions.add(.of(name, _typeOfElement(element), modifiers));
    }
  }

  /// Adds [name], which declares [element].
  void _addDeclared(Token? name, Element? element) =>
      _add(name, element, modifiers: const {'declaration'});

  @override
  void visitAnnotation(Annotation node) {
    if (node.arguments case final arguments?) {
      regions
        ..add(
          .new(
            node.offset,
            arguments.beginToken.end - node.offset,
            'annotation',
          ),
        )
        ..add(.of(arguments.endToken, 'annotation'));
    } else {
      regions.add(.of(node, 'annotation'));
    }
    super.visitAnnotation(node);
  }

  /// Adds [node]. The name of an annotation that names a class, a
  /// constructor or a variable gets the `annotation` modifier.
  @override
  void visitSimpleIdentifier(SimpleIdentifier node) {
    final parent = node.parent;
    // The left side of an assignment names the setter that it writes.
    final element = assignmentTo(node)?.writeElement ?? node.element;
    final inAnnotation =
        parent is Annotation ||
        parent is PrefixedIdentifier && parent.parent is Annotation;
    _add(
      node.token,
      element,
      modifiers: {
        // The server marks a top-level variable and a static field as
        // declared wherever they are named, such as in `show`.
        if (node.inDeclarationContext() && element is! PrefixElement ||
            parent is ConstructorDeclaration &&
                parent.typeName == node &&
                element is ClassElement ||
            element is TopLevelVariableElement ||
            element is FieldElement &&
                element.isStatic &&
                !element.isEnumConstant)
          'declaration',
        if (inAnnotation &&
            (element is InterfaceElement ||
                element is ConstructorElement ||
                element is PropertyAccessorElement ||
                element is PropertyInducingElement))
          'annotation',
      },
    );
  }

  /// Adds the name of [node], unless it is `void`, which is a keyword.
  @override
  void visitNamedType(NamedType node) {
    if (node.importPrefix case final prefix?) {
      _add(prefix.name, prefix.element);
    }
    if (node.name.keyword != .VOID) {
      _add(node.name, node.element);
    }
    super.visitNamedType(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitFunctionDeclaration(FunctionDeclaration node) {
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitFunctionDeclaration(node);
  }

  @override
  void visitMethodDeclaration(MethodDeclaration node) {
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitMethodDeclaration(node);
  }

  /// Adds the name of [node], and for one declared with `new` or `factory`
  /// in place of its class name, such as `new named()`, that keyword, which
  /// declares it too.
  @override
  void visitConstructorDeclaration(ConstructorDeclaration node) {
    if ((node.typeName, node.newKeyword ?? node.factoryKeyword) case (
      null,
      final keyword?,
    )) {
      regions.add(.of(keyword, 'keyword', const {'declaration'}));
    }
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitConstructorDeclaration(node);
  }

  /// Adds the name of each parameter, which declares it unless it is a
  /// `this.` parameter. A declaring parameter of a primary constructor
  /// declares its field.
  @override
  void visitFormalParameterList(FormalParameterList node) {
    for (final parameter in node.parameters) {
      final element = parameter.declaredFragment?.element;
      if (element case FieldFormalParameterElement(isDeclaring: false)) {
        _add(parameter.name, element);
      } else {
        _addDeclared(parameter.name, element);
      }
    }
    super.visitFormalParameterList(node);
  }

  @override
  void visitDeclaredIdentifier(DeclaredIdentifier node) {
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitDeclaredIdentifier(node);
  }

  @override
  void visitDeclaredVariablePattern(DeclaredVariablePattern node) {
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitDeclaredVariablePattern(node);
  }

  @override
  void visitWildcardPattern(WildcardPattern node) {
    _addDeclared(node.name, null);
    super.visitWildcardPattern(node);
  }

  @override
  void visitCatchClauseParameter(CatchClauseParameter node) {
    _addDeclared(node.name, node.declaredFragment?.element);
    super.visitCatchClauseParameter(node);
  }

  @override
  void visitTypeParameter(TypeParameter node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitTypeParameter(node);
  }

  @override
  void visitEnumConstantDeclaration(EnumConstantDeclaration node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitEnumConstantDeclaration(node);
  }

  /// Adds the name of [node] as a declaration. As in the analysis server,
  /// the names of classes and extension types are declarations, and the
  /// names of mixins, enums, extensions and typedefs are not.
  @override
  void visitClassDeclaration(ClassDeclaration node) {
    _addDeclared(node.namePart.typeName, node.declaredFragment?.element);
    super.visitClassDeclaration(node);
  }

  @override
  void visitMixinDeclaration(MixinDeclaration node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitMixinDeclaration(node);
  }

  @override
  void visitEnumDeclaration(EnumDeclaration node) {
    _add(node.namePart.typeName, node.declaredFragment?.element);
    super.visitEnumDeclaration(node);
  }

  @override
  void visitExtensionDeclaration(ExtensionDeclaration node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitExtensionDeclaration(node);
  }

  /// Adds the name and the `type` keyword of [node].
  @override
  void visitExtensionTypeDeclaration(ExtensionTypeDeclaration node) {
    regions.add(.of(node.typeKeyword, 'keyword'));
    _addDeclared(
      extensionTypeNamePart(node).typeName,
      node.declaredFragment?.element,
    );
    super.visitExtensionTypeDeclaration(node);
  }

  @override
  void visitClassTypeAlias(ClassTypeAlias node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitClassTypeAlias(node);
  }

  @override
  void visitFunctionTypeAlias(FunctionTypeAlias node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitFunctionTypeAlias(node);
  }

  @override
  void visitGenericTypeAlias(GenericTypeAlias node) {
    _add(node.name, node.declaredFragment?.element);
    super.visitGenericTypeAlias(node);
  }

  /// Adds `part of` as one keyword.
  @override
  void visitPartOfDirective(PartOfDirective node) {
    _addKeyword(node.partKeyword, node.ofKeyword);
    super.visitPartOfDirective(node);
  }

  /// Adds `sync*` and `async*` as one keyword.
  @override
  void visitBlockFunctionBody(BlockFunctionBody node) {
    if ((node.keyword, node.star) case (final keyword?, final star?)) {
      _addKeyword(keyword, star);
    }
    super.visitBlockFunctionBody(node);
  }

  /// Adds the names of the dotted name that a conditional import tests, such
  /// as `dart.library.io`, where `library` is no keyword. From analyzer
  /// 12.0.0 on, they are tokens of the dotted name; before, they are
  /// identifiers, which [visitSimpleIdentifier] adds.
  @override
  void visitConfiguration(Configuration node) {
    for (final name in node.name.childEntities.whereType<Token>()) {
      if (name.type != .PERIOD) {
        _add(name, null);
      }
    }
    super.visitConfiguration(node);
  }

  /// Adds the keyword from [first] to [last] as one region.
  void _addKeyword(Token first, Token last) {
    regions.add(.new(first.offset, last.end - first.offset, 'keyword'));
    covered.add(last.offset);
  }

  @override
  void visitExtensionOverride(ExtensionOverride node) {
    _add(node.name, node.element);
    super.visitExtensionOverride(node);
  }

  @override
  void visitArgumentList(ArgumentList node) {
    _addNamesOf(node.arguments);
    super.visitArgumentList(node);
  }

  @override
  void visitRecordLiteral(RecordLiteral node) {
    _addNamesOf(node.fields);
    super.visitRecordLiteral(node);
  }

  /// Adds the name of each of [arguments] that is named, also one that is a
  /// keyword elsewhere, such as `source` in `pick(source: a)`. Before
  /// analyzer 13.0.0, the name is an identifier, which [visitSimpleIdentifier]
  /// adds.
  void _addNamesOf(Iterable<AstNode> arguments) {
    for (final argument in arguments) {
      if (argumentNameOf(argument) case (:final name, colon: _)) {
        _add(name, null);
      }
    }
  }

  @override
  void visitPatternField(PatternField node) {
    if (node.name?.name case final name?) {
      // A field of a record pattern has no element, but reads a property.
      if (node.parent is RecordPattern) {
        regions.add(.of(name, 'property'));
      } else {
        _add(name, node.element);
      }
    }
    super.visitPatternField(node);
  }

  /// Leaves out the names of the fields of [node], which the server gives no
  /// tokens.
  @override
  void visitRecordTypeAnnotation(RecordTypeAnnotation node) {
    covered.addAll([
      for (final field in [
        ...node.positionalFields,
        ...?node.namedFields?.fields,
      ])
        ?field.name?.offset,
    ]);
    super.visitRecordTypeAnnotation(node);
  }

  /// The type of a token that names [element].
  static String _typeOfElement(Element? element) => switch (element) {
    EnumElement() => 'enum',
    InterfaceElement() || ExtensionElement() => 'class',
    FieldElement(isEnumConstant: true) ||
    GetterElement(variable: FieldElement(isEnumConstant: true)) => 'enumMember',
    PropertyAccessorElement() => 'property',
    FieldElement() ||
    TopLevelVariableElement() ||
    LocalVariableElement() ||
    PrefixElement() => 'variable',
    ConstructorElement() || MethodElement() => 'method',
    TopLevelFunctionElement() || LocalFunctionElement() => 'function',
    FormalParameterElement() => 'parameter',
    TypeParameterElement() => 'typeParameter',
    TypeAliasElement() => 'type',
    LabelElement() => 'label',
    _ => 'source',
  };
}
