/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';

/// The clause keywords after which a type passes its members on: `extends`,
/// `with`, and the `=` of `class A = B with M;`.
const _inheritingClauses = {'extends', 'with', '='};

const _clauseKeywords = {'extends', 'with', 'implements', 'on', '='};

final _word = RegExp(r'[A-Za-z_$][\w$]*');

extension ExposedTypes on SourceIndex {
  /// The private types declared in [path] whose members other libraries can
  /// reach through a public type of the same file: one that extends it, mixes
  /// it in or, as an extension type, implements it, directly or through
  /// another such private type. Like `_Base` in
  /// `class Circle extends _Base {}`, where `Circle().area()` calls
  /// `_Base.area`.
  ///
  /// [unit] is the outline of [path]. A subtype in another part of the
  /// library is not seen.
  Set<String> exposedPrivateTypes(String path, Outline unit) {
    final text = stripComments(content(path));
    final supertypes = <String, List<String>>{
      for (final type in unit.children)
        if (_headerStart(path, type) case final start?)
          type.element.name: _privateSupertypes(
            text,
            start,
            inherits: type.element.kind == .extensionType
                ? const {'implements'}
                : _inheritingClauses,
          ),
    };
    final exposed = <String>{};
    final pending = [
      for (final MapEntry(key: name, value: types) in supertypes.entries)
        if (!isPrivateName(name)) ...types,
    ];
    while (pending.isNotEmpty) {
      final type = pending.removeLast();
      if (exposed.add(type)) {
        pending.addAll(supertypes[type] ?? const []);
      }
    }
    return exposed;
  }

  /// The offset right after the name of [type], or `null` when it is no class,
  /// mixin, enum or extension type.
  int? _headerStart(String path, Outline type) => switch (type.element) {
    OutlineElement(
      kind: .class$ || .classTypeAlias || .mixin || .enum$ || .extensionType,
      :final range?,
    ) =>
      offsetOf(path, range.end),
    _ => null,
  };
}

/// The private types named in [inherits] clauses of the header that starts at
/// [start] in [text].
List<String> _privateSupertypes(
  String text,
  int start, {
  required Set<String> inherits,
}) {
  final types = <String>[];
  String? clause;
  for (final word in _headerWords(text, start)) {
    if (_clauseKeywords.contains(word)) {
      clause = word;
    } else if (inherits.contains(clause) && isPrivateName(word)) {
      types.add(word);
    }
  }
  return types;
}

/// The words of the header that starts at [start] in [text], up to its body
/// or `;`, and its `=`. Type arguments, type parameter bounds and a primary
/// constructor's parameters are skipped.
Iterable<String> _headerWords(String text, int start) sync* {
  var depth = 0;
  var i = start;
  while (i < text.length) {
    if (_word.matchAsPrefix(text, i) case final match?) {
      if (depth == 0) {
        yield match[0]!;
      }
      i = match.end;
      continue;
    }
    final char = text[i];
    depth += _nesting(char);
    if (depth == 0 && (char == '{' || char == ';')) {
      return;
    }
    if (depth == 0 && char == '=') {
      yield char;
    }
    i++;
  }
}

/// How [char] changes the bracket depth.
int _nesting(String char) => switch (char) {
  '<' || '(' || '[' => 1,
  '>' || ')' || ']' => -1,
  _ => 0,
};
