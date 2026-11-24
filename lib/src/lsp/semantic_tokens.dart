import 'package:ciach/src/source/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position, Range;

/// The token type and modifier names a `semanticTokens` response indexes into.
final class SemanticTokensLegend {
  const SemanticTokensLegend({
    required this.tokenTypes,
    required this.tokenModifiers,
  });

  /// The legend from the server's `initialize` capabilities, or [empty].
  factory SemanticTokensLegend.fromCapabilities(Map<String, Object?> json) =>
      switch (json['semanticTokensProvider']) {
        {
          'legend': {
            'tokenTypes': final List<Object?> types,
            'tokenModifiers': final List<Object?> modifiers,
          },
        } =>
          .new(
            tokenTypes: [for (final t in types) '$t'],
            tokenModifiers: [for (final m in modifiers) '$m'],
          ),
        _ => empty,
      };

  static const empty = SemanticTokensLegend(tokenTypes: [], tokenModifiers: []);

  final List<String> tokenTypes;
  final List<String> tokenModifiers;
}

/// A token on one line of a file, as classified by the analysis server. A
/// multi-line comment or string arrives as one token per line. A `[Foo]` link
/// in a doc comment is its own `class` token, not part of the comment.
final class SemanticToken {
  const SemanticToken({
    required this.line,
    required this.character,
    required this.length,
    required this.type,
    required this.modifiers,
    required this.text,
  });

  final int line;
  final int character;
  final int length;
  final String type;
  final Set<String> modifiers;

  final String text;

  Position get start => .new(line: line, character: character);

  int get end => character + length;

  bool get isComment => type == 'comment';

  bool get isDocComment => isComment && modifiers.contains('documentation');

  bool get isKeyword => type == 'keyword';

  /// Whether this is the `@`, `(` or `)` of an annotation.
  bool get isAnnotationPunctuation => type == 'annotation';

  bool get isImportPrefix => modifiers.contains('importPrefix');

  bool get isDeclaration => modifiers.contains('declaration');

  /// Whether this is the name of an `@[name]` annotation.
  bool isAnnotationNamed(String name) =>
      modifiers.contains('annotation') && text == name;

  /// The value of this string literal without its quotes, such as
  /// `vm:entry-point` for `'vm:entry-point'`, or `null` when this is not a
  /// string literal or has an escape or an interpolation.
  String? get stringValue => type == 'string'
      ? _plainString.firstMatch(text)?.namedGroup('value')
      : null;
}

/// A string literal with no escape and no interpolation, in any quotes:
/// `'a'`, `"a"`, `r'a'` or `'''a'''`. The semantic token of a string
/// literal holds its source text, quotes included.
final _plainString = RegExp(
  r'''^r?(?<quote>'{3}|"{3}|'|")(?<value>[^\\$'"]*)\k<quote>$''',
);

/// The name that follows the `@` of an annotation, as
/// [SemanticTokenLookup.annotationNames] returns it.
typedef AnnotationName = ({
  /// The token of the name: the class or typedef whose constructor the
  /// annotation calls, or the constant that it reads.
  SemanticToken token,

  /// The name as written, with its import prefix: `previews.Preview`.
  String written,

  /// Whether the annotation reads a constant, as `@preview` and
  /// `@Holder.held` do, rather than calling a constructor.
  bool readsConstant,

  /// The value of the string literal that the annotation's first argument
  /// is, as [SemanticTokenLookup.annotationArgumentAfter] returns it.
  String? argument,
});

/// Decodes the relative-encoded [data] of a `semanticTokens/full` response.
/// Tokens outside the legend or the file are dropped.
List<SemanticToken> decodeSemanticTokens(
  List<int> data,
  SemanticTokensLegend legend,
  List<String> lines,
) {
  final tokens = <SemanticToken>[];
  var line = 0;
  var character = 0;
  for (var i = 0; i + 4 < data.length; i += 5) {
    final deltaLine = data[i];
    if (deltaLine > 0) {
      line += deltaLine;
      character = data[i + 1];
    } else {
      character += data[i + 1];
    }
    final length = data[i + 2];
    final typeIndex = data[i + 3];
    final modifierBits = data[i + 4];
    if (typeIndex < 0 ||
        typeIndex >= legend.tokenTypes.length ||
        line < 0 ||
        line >= lines.length ||
        character < 0 ||
        character + length > lines[line].length) {
      continue;
    }
    tokens.add(
      .new(
        line: line,
        character: character,
        length: length,
        type: legend.tokenTypes[typeIndex],
        modifiers: {
          for (final (bit, tokenModifier) in legend.tokenModifiers.indexed)
            if ((modifierBits >> bit) & 1 == 1) tokenModifier,
        },
        text: lines[line].substring(character, character + length),
      ),
    );
  }
  return tokens;
}

/// Lookups over a file's tokens, which are ordered by position.
extension SemanticTokenLookup on List<SemanticToken> {
  /// The index of the first token starting at or after [position].
  int firstIndexAtOrAfter(Position position) {
    var lo = 0;
    var hi = length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (this[mid].start.isBefore(position)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  /// The first token on [line].
  SemanticToken? firstOnLine(int line) {
    final i = firstIndexAtOrAfter(.new(line: line, character: 0));
    return i < length && this[i].line == line ? this[i] : null;
  }

  /// The token starting at [position].
  SemanticToken? startingAt(Position position) {
    final i = firstIndexAtOrAfter(position);
    return i < length && this[i].start == position ? this[i] : null;
  }

  /// The last token starting within [range].
  SemanticToken? lastIn(Range range) {
    final i = firstIndexAtOrAfter(range.end) - 1;
    return i >= 0 && !this[i].start.isBefore(range.start) ? this[i] : null;
  }

  /// The tokens starting at or after [from] and before [to].
  Iterable<SemanticToken> between(Position from, Position to) =>
      skip(firstIndexAtOrAfter(from)).takeWhile((t) => t.start.isBefore(to));

  /// Returns the name of each annotation among these tokens: `Preview` in
  /// `@Preview()`, `@Preview.named()` and `@prefix.Preview()`, a typedef such
  /// as `AliasPreview` in `@AliasPreview()`, and the constants `preview` in
  /// `@preview` and `held` in `@Holder.held`.
  Iterable<AnnotationName> annotationNames() sync* {
    for (final (i, t) in indexed) {
      if (_annotationNameAfter(i) case final name? when t.text == '@') {
        yield name;
      }
    }
  }

  /// Returns the value of the string literal that is the first argument of
  /// the annotation whose `@` or name is at [index]: `vm:entry-point` in
  /// `@pragma('vm:entry-point')` and in `@core.pragma('vm:entry-point')`.
  /// Returns `null` for an annotation without arguments, such as `@story`,
  /// and when the first argument is not a plain string literal.
  String? annotationArgumentAfter(int index) {
    // The server gives the punctuation of an annotation, and nothing else,
    // the type `annotation`: `@`, `(`, `)`, `.`, `<`, and `>.` or `>(` after
    // type arguments. The next `@` starts another annotation.
    final i = indexWhere(
      (t) => t.type == 'annotation' && (t.text == '@' || t.text.endsWith('(')),
      index + 1,
    );
    return i >= 0 && this[i].text != '@'
        ? elementAtOrNull(i + 1)?.stringValue
        : null;
  }

  /// Returns the name of the annotation that starts with the `@` at [index].
  AnnotationName? _annotationNameAfter(int index) {
    final argument = annotationArgumentAfter(index);
    return switch (skip(index + 1).take(5).toList()) {
      [
        SemanticToken(isImportPrefix: true, :final text),
        SemanticToken(text: '.'),
        ...final rest,
      ] =>
        _annotationNameIn(rest, '$text.', argument),
      final rest => _annotationNameIn(rest, '', argument),
    };
  }

  /// Returns the name at the start of [tokens]. [tokens] follow the `@` of an
  /// annotation and its import [prefix], and [argument] is the annotation's
  /// first argument.
  static AnnotationName? _annotationNameIn(
    List<SemanticToken> tokens,
    String prefix,
    String? argument,
  ) => switch (tokens) {
    // `held` in `@Holder.held` is a static constant of the class `Holder`.
    [
      SemanticToken(type: 'class' || 'type'),
      SemanticToken(text: '.'),
      final constant && SemanticToken(type: 'property'),
      ...,
    ] ||
    [final constant && SemanticToken(type: 'property'), ...] => (
      token: constant,
      written: '$prefix${constant.text}',
      readsConstant: true,
      argument: argument,
    ),
    [final name && SemanticToken(type: 'class' || 'type'), ...] => (
      token: name,
      written: '$prefix${name.text}',
      readsConstant: false,
      argument: argument,
    ),
    _ => null,
  };
}
