/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Builds the tokens of a resolved file as the analysis server's semantic
/// tokens list them: every identifier, keyword, literal and comment, with no
/// punctuation but the `@` and the parentheses of an annotation.
///
/// It follows `DartUnitHighlightsComputer` and `SemanticTokenEncoder` in the
/// analysis server, whose tokens ciach read over LSP before, for what ciach
/// reads: where each token is, whether it is a comment, a doc comment, a
/// keyword or a string, whether it names a class or a property, and whether
/// it declares something or names an annotation. Other identifiers get a
/// type from their element, which can differ from the server's.
library;

import 'dart:collection';
import 'dart:math';

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/syntactic_entity.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:ciach/src/analysis/analyzer_versions.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/source/semantic_tokens.dart';

/// Returns the tokens of [unit], whose text is [content] and whose lines
/// [lineInfo] holds, in order.
List<SemanticToken> unitTokens(
  CompilationUnit unit,
  String content,
  LineInfo lineInfo,
) {
  final visitor = _Regions()..visitCompilationUnit(unit);
  final regions = visitor.regions;
  final named = {
    for (final region in regions) region.offset,
    ...visitor.covered,
  };
  for (Token? token = unit.beginToken; token != null; token = token.next) {
    for (
      Token? comment = token.precedingComments;
      comment != null;
      comment = comment.next
    ) {
      regions.add(
        .of(comment, 'comment', {if (_isDocComment(comment)) 'documentation'}),
      );
    }
    if (token.isEof) {
      break;
    }
    if (!named.contains(token.offset)) {
      if (_typeOf(token) case final type?) {
        regions.add(.of(token, type));
      }
    }
  }
  regions.sort(_Region.byPlace);
  final lines = content.split('\n');
  return [
    for (final region in _withoutOverlaps(regions))
      ..._onEachLine(region, lineInfo, lines),
  ];
}

/// The type of a [token] that names nothing: a keyword, a literal, or `null`
/// for punctuation.
String? _typeOf(Token token) => switch (token) {
  Token(type: .STRING) => 'string',
  Token(type: .INT || .DOUBLE || .HEXADECIMAL) => 'number',
  Token(keyword: .TRUE || .FALSE) => 'boolean',
  Token(keyword: _?) => 'keyword',
  Token(type: .IDENTIFIER) => 'source',
  _ => null,
};

/// Whether [comment] is a `///` or `/**` doc comment.
bool _isDocComment(Token comment) => switch (comment.type) {
  .SINGLE_LINE_COMMENT => comment.lexeme.startsWith('///'),
  .MULTI_LINE_COMMENT => comment.lexeme.startsWith('/**'),
  _ => false,
};

/// The text from [offset] to [offset] + [length] as one token of [type] with
/// [modifiers].
final class _Region {
  _Region(this.offset, this.length, this.type, [this.modifiers = const {}]);

  _Region.of(
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
  static int byPlace(_Region a, _Region b) =>
      switch (a.offset.compareTo(b.offset)) {
        0 => b.length.compareTo(a.length),
        final byStart => byStart,
      };
}

/// [sorted] with each region that holds others split around them, as the
/// server's `splitOverlappingTokens` does: `@pragma(` around `pragma` gives
/// `@`, `pragma` and `(`.
Iterable<_Region> _withoutOverlaps(List<_Region> sorted) sync* {
  final open = ListQueue<_Region>();
  Iterable<_Region> close(int from, int to) sync* {
    var start = from;
    while (open.isNotEmpty) {
      final last = open.last;
      final end = min(last.end, to);
      if (end > start) {
        yield .new(start, end - start, last.type, last.modifiers);
        start = end;
      }
      if (last.end > to) {
        return;
      }
      open.removeLast();
    }
  }

  if (sorted.isEmpty) {
    return;
  }
  var from = sorted.first.offset;
  for (final region in sorted) {
    yield* close(from, region.offset);
    open.addLast(region);
    from = region.offset;
  }
  yield* close(from, open.first.end);
}

/// The token of [region] on each line of [lines] that it spans. Like the
/// server, it splits the region at line starts and lets each part but the
/// last run to the start of the next line, and like ciach's decoder of the
/// server's tokens, it drops a part that runs past the end of its line, so a
/// region that spans lines keeps only its last line.
Iterable<SemanticToken> _onEachLine(
  _Region region,
  LineInfo lineInfo,
  List<String> lines,
) sync* {
  final start = lineInfo.positionOf(region.offset);
  final end = lineInfo.positionOf(region.end);
  for (var line = start.line; line <= end.line; line++) {
    final from = line == start.line ? start.character : 0;
    final to = line == end.line
        ? end.character
        : lineInfo.getOffsetOfLine(line + 1) - lineInfo.getOffsetOfLine(line);
    if (to <= lines[line].length) {
      yield .new(
        line: line,
        character: from,
        length: to - from,
        type: region.type,
        modifiers: region.modifiers,
        text: lines[line].substring(from, to),
      );
    }
  }
}

/// Collects a region for each name in a file, typed after what it names, and
/// for the `@` and parentheses of each annotation.
final class _Regions extends RecursiveAstVisitor<void> {
  final regions = <_Region>[];

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
    final element = _writtenOrRead(node);
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

  /// Adds the name of [node], which declares it, as the name of no other
  /// type declaration does.
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
  /// as `dart.library.io`, where `library` is no keyword.
  @override
  void visitConfiguration(Configuration node) {
    for (
      Token? token = node.name.beginToken;
      token != null;
      token = token.next
    ) {
      if (token.type != .PERIOD) {
        _add(token, null);
      }
      if (token == node.name.endToken) {
        break;
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

  /// Adds the name of each argument that [node] passes by name and that is a
  /// keyword elsewhere, such as `source` in `pick(source: a)`. From analyzer
  /// 13.0.0 on, it is a token of the argument rather than an identifier.
  @override
  void visitArgumentList(ArgumentList node) {
    for (final AstNode argument in node.arguments) {
      final name = argument.beginToken;
      if (name.keyword != null && name.next?.type == .COLON) {
        _add(name, null);
      }
    }
    super.visitArgumentList(node);
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

  /// Leaves out the name of [node], which the server gives no token.
  @override
  void visitRecordTypeAnnotationNamedField(
    RecordTypeAnnotationNamedField node,
  ) {
    covered.add(node.name.offset);
    super.visitRecordTypeAnnotationNamedField(node);
  }

  /// Leaves out the name of [node], which the server gives no token.
  @override
  void visitRecordTypeAnnotationPositionalField(
    RecordTypeAnnotationPositionalField node,
  ) {
    if (node.name case final name?) {
      covered.add(name.offset);
    }
    super.visitRecordTypeAnnotationPositionalField(node);
  }

  /// The element that [node] names: the setter of an assignment's left side,
  /// the getter of a compound one's.
  static Element? _writtenOrRead(SimpleIdentifier node) {
    final target = switch (node.parent) {
      PrefixedIdentifier(:final identifier) && final parent
          when identifier == node =>
        parent,
      PropertyAccess(:final propertyName) && final parent
          when propertyName == node =>
        parent,
      _ => node,
    };
    return switch (target.parent) {
      AssignmentExpression(
        :final leftHandSide,
        writeElement: final writeElement?,
      ) ||
      PrefixExpression(
        operand: final leftHandSide,
        writeElement: final writeElement?,
      ) ||
      PostfixExpression(
        operand: final leftHandSide,
        writeElement: final writeElement?,
      ) when leftHandSide == target => writeElement,
      _ => node.element,
    };
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
