/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// The syntax around a reference or a declaration in a parsed file, for the
/// questions of `FileSyntax`. Each function takes the offset of the name.
library;

import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/token.dart';
import 'package:analyzer/source/line_info.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';

/// See [FileSyntax.isDocReference].
bool isDocReferenceAt(CompilationUnit unit, int offset) =>
    unit.nodeCovering(offset: offset)?.thisOrAncestorOfType<Comment>() != null;

/// See [FileSyntax.isTypePattern].
bool isTypePatternAt(CompilationUnit unit, int offset) =>
    switch (unit.nodeCovering(offset: offset)) {
      NamedType(
        parent: ObjectPattern(parent: GuardedPattern()) ||
            DeclaredVariablePattern(parent: GuardedPattern()),
      ) =>
        true,
      _ => false,
    };

/// See [FileSyntax.isEnumValuesAccess].
bool isEnumValuesAccessAt(CompilationUnit unit, int offset) {
  final name = unit.nodeCovering(offset: offset);
  // `prefix.Color` names the enum with its import prefix.
  final reference = switch (name?.parent) {
    PrefixedIdentifier(:final identifier) && final prefixed
        when identifier == name =>
      prefixed,
    _ => name,
  };
  return switch (reference?.parent) {
    PrefixedIdentifier(
      :final prefix,
      identifier: SimpleIdentifier(name: 'values'),
    ) =>
      prefix == reference,
    PropertyAccess(
      :final target,
      propertyName: SimpleIdentifier(name: 'values'),
    ) =>
      target == reference,
    _ => false,
  };
}

/// See [FileSyntax.isStateTypeArgument].
bool isStateTypeArgumentAt(CompilationUnit unit, int offset) => switch (unit
    .nodeCovering(offset: offset)) {
  NamedType(
    parent: TypeArgumentList(
      arguments: [_],
      parent: NamedType(name: Token(lexeme: 'State'), parent: ExtendsClause()),
    ),
  ) =>
    true,
  _ => false,
};

/// See [FileSyntax.clauseAt].
({Clause clause, Range entry})? clauseAt(
  CompilationUnit unit,
  int offset,
  String name,
) {
  final lineInfo = unit.lineInfo;
  Clause clauseOf(AstNode clause, Token keyword, List<NamedType> entries) => (
    range: lineInfo.rangeOfEntity(clause),
    entries: entries.map(lineInfo.rangeOfEntity).toList(),
    whole: lineInfo.rangeOf(_spaceBefore(lineInfo, keyword), clause.end),
    keepsOne: switch (clause) {
      WithClause(parent: ClassTypeAlias()) => true,
      _ => false,
    },
  );
  return switch (unit.nodeCovering(offset: offset)) {
    NamedType(importPrefix: null, name: Token(:final lexeme), :final parent) &&
            final entry
        when lexeme == name =>
      switch (parent) {
        WithClause(:final withKeyword, :final mixinTypes) => (
          clause: clauseOf(parent, withKeyword, mixinTypes),
          entry: lineInfo.rangeOfEntity(entry),
        ),
        ImplementsClause(:final implementsKeyword, :final interfaces) => (
          clause: clauseOf(parent, implementsKeyword, interfaces),
          entry: lineInfo.rangeOfEntity(entry),
        ),
        _ => null,
      },
    _ => null,
  };
}

/// Where the whitespace before [keyword] starts: after the token or the
/// comment before it, or at the start of [keyword]'s line when a `//`
/// comment comes right before it.
int _spaceBefore(LineInfo lineInfo, Token keyword) {
  Token? lastComment;
  for (
    Token? comment = keyword.precedingComments;
    comment != null;
    comment = comment.next
  ) {
    lastComment = comment;
  }
  return switch (lastComment) {
    Token(type: .SINGLE_LINE_COMMENT, :final end) =>
      lineInfo.getOffsetOfLineAfter(end),
    final Token comment => comment.end,
    null => keyword.previous!.end,
  };
}

/// See [FileSyntax.declaratorAt].
({VariableStatement statement, Range declarator})? declaratorAt(
  CompilationUnit unit,
  int offset,
) {
  final lineInfo = unit.lineInfo;
  return switch (unit.nodeCovering(offset: offset)) {
    VariableDeclaration(
          parent: VariableDeclarationList(
            :final variables,
            parent: final AnnotatedNode statement &&
                (FieldDeclaration() || TopLevelVariableDeclaration()),
          ),
        ) &&
        final declarator =>
      (
        statement: (
          range: lineInfo.rangeOfEntity(statement),
          declarators: variables.map(lineInfo.rangeOfEntity).toList(),
        ),
        declarator: lineInfo.rangeOfEntity(declarator),
      ),
    _ => null,
  };
}

/// See [FileSyntax.isInBody]. [start] and [end] are the offsets of the
/// declaration's code.
bool isInBodyAt(CompilationUnit unit, int offset, int start, int end) {
  for (
    var node = unit.nodeCovering(offset: offset);
    node != null && node.offset >= start;
    node = node.parent
  ) {
    if (node case FunctionBody(
      :final offset,
    ) when node.end == end && offset != start) {
      return true;
    }
  }
  return false;
}
