/// The parameters of a function, method or constructor, whether its body reads
/// them, and whether a reference to it calls it, read from the server's
/// semantic tokens and selection ranges cached in [SourceIndex].
library;

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Range;

extension Parameters on SourceIndex {
  /// Returns the parameter declarations between the start and the end of
  /// [function] in [path]: those of its own parameter list, and those of the
  /// function types and closures in it. `super.x` is left out, because it
  /// always passes the value on, and so is `this.x`, which the server names a
  /// field.
  ///
  /// [ownParameters] needs the selection ranges at these positions.
  List<SemanticToken> parameterDeclarations(String path, Outline function) {
    final tokens = semanticTokens(path);
    if (tokens == null) {
      return const [];
    }
    final inFunction = tokens
        .between(function.codeRange.start, function.codeRange.end)
        .toList();
    return [
      for (final (i, token) in inFunction.indexed)
        if (token.type == 'parameter' &&
            token.modifiers.contains('declaration') &&
            !_isSuper(i == 0 ? null : inFunction[i - 1]))
          token,
    ];
  }

  static bool _isSuper(SemanticToken? token) => switch (token) {
    SemanticToken(isKeyword: true, text: 'super') => true,
    _ => false,
  };

  /// Returns the declarations among [parameterDeclarations] that [function]
  /// in [path] declares itself, in its own parameter list. A declaring
  /// parameter of a primary constructor, such as `final int x`, is a field and
  /// is left out.
  List<SemanticToken> ownParameters(String path, Outline function) => [
    for (final token in parameterDeclarations(path, function))
      if (parameterListOf(path, function, token) != null &&
          !_isDeclaring(path, token))
        token,
  ];

  /// Returns the range of [function]'s own parameter list in [path] when it
  /// declares [parameter], and `null` when a closure or a function type in
  /// [function] does.
  ///
  /// A parameter's syntax node is a child of the parameter list, or a child of
  /// a default value that is. The list is a child of [function] that starts
  /// after its name; for a function, a node that starts with the list, the
  /// parameters and the body, stands between them. A closure's parameter
  /// list, or a function type's, is further down.
  Range? parameterListOf(
    String path,
    Outline function,
    SemanticToken parameter,
  ) {
    final name = function.element.range?.end;
    final node = selectionRangeAt(path, parameter.start);
    if (name == null || node == null) {
      return null;
    }
    bool isFunction(Range? range) =>
        range == function.codeRange || range == function.range;
    return [node.parent, node.parent?.parent].firstWhereOrNull((list) {
      if (list == null || !name.atOrBefore(list.range.start)) {
        return false;
      }
      final parent = list.parent;
      return isFunction(parent?.range) ||
          (parent?.range.start == list.range.start &&
              isFunction(parent?.parent?.range));
    })?.range;
  }

  /// Whether [parameter] is a declaring parameter of a primary constructor:
  /// `var` or `final` stands between the start of its syntax node and its
  /// name.
  bool _isDeclaring(String path, SemanticToken parameter) =>
      selectionRangeAt(path, parameter.start)?.range.start.let(
        (start) => semanticTokens(path)
            ?.between(start, parameter.start)
            .any((t) => t.isKeyword && const {'var', 'final'}.contains(t.text)),
      ) ??
      false;

  /// Whether [scope] in [path] reads [parameter] after declaring it. A
  /// closure parameter of the same name counts as a read, so a parameter that
  /// one shadows is never reported.
  bool isRead(String path, Range scope, SemanticToken parameter) =>
      semanticTokens(path)
          ?.between(parameter.start, scope.end)
          .any(
            (t) =>
                t.type == 'parameter' &&
                t.text == parameter.text &&
                t.modifiers.none(const {'declaration', 'label'}.contains),
          ) ??
      true;

  /// Whether [function] in [path], whose own parameter list is at
  /// [parameterList], has a body: it isn't `external`, and it doesn't end
  /// with the `;` of an abstract method right after the list.
  ///
  /// The tokens leave out punctuation, so an abstract method has no token
  /// after its list, and neither has an empty body, `{}`, which ends with `}`.
  bool hasBody(String path, Outline function, Range parameterList) {
    final tokens = semanticTokens(path);
    final end = offsetOf(path, function.codeRange.end);
    return tokens != null &&
        end != null &&
        tokens
            .between(function.codeRange.start, parameterList.start)
            .none((t) => t.isKeyword && t.text == 'external') &&
        (tokens.between(parameterList.end, function.codeRange.end).isNotEmpty ||
            content(path)[end - 1] == '}');
  }

  /// Whether the reference [loc] calls what it names, as in `f(1)`, `c.m(1)`
  /// or `C.named(1)`, rather than tearing it off, as in `list.forEach(f)`,
  /// `C.new` or `f<int>`. Needs the selection range at the start of [loc].
  ///
  /// The server's syntax nodes have no kinds, so the character after the name
  /// and the one that ends the node around the name tell them apart: a call
  /// continues with type arguments or arguments, and ends with the `)` of its
  /// arguments.
  bool isCall(Location loc) {
    final path = SourceIndex.pathOf(loc.uri);
    var node = selectionRangeAt(path, loc.range.start);
    while (node != null && node.range.end.atOrBefore(loc.range.end)) {
      node = node.parent;
    }
    final text = content(path);
    final next = offsetOf(
      path,
      loc.range.end,
    )?.let((end) => nextNonWhitespace(text, end));
    final last = node?.range.end.let((end) => offsetOf(path, end));
    return next != null &&
        last != null &&
        const {'(', '<'}.contains(text[next]) &&
        text[last - 1] == ')';
  }
}
