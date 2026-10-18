import 'package:ciach/src/source/comment_stripping.dart';
import 'package:ciach/src/util/reachability.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';

/// An `import`, `export` or `part` directive, read without the analyzer.
extension type Directive._(RegExpMatch _match) {
  /// The directives in [content] that are not commented out. Offsets index
  /// [content].
  static Iterable<Directive> allIn(String content) =>
      _directive.allMatches(stripComments(content)).map(Directive._);

  /// `import`, `export` or `part`.
  String get keyword => _match.namedGroup('keyword')!;

  /// Everything between the keyword and the `;`.
  String get body => _match.namedGroup('body')!;

  int get start => _match.start;

  int get end => _match.end;

  bool get isPartOf => keyword == 'part' && _partOf.hasMatch(body);

  /// Whether it has an `if (…)` clause.
  bool get isConditional => _condition.hasMatch(body);

  /// The URIs it names, the default one first. Strings compared in its
  /// conditions are not URIs.
  List<RegExpMatch> get uris {
    final conditions = _condition.allMatches(body).toList();
    return uriLiteral
        .allMatches(body)
        .where(
          (uri) =>
              conditions.none((c) => c.start <= uri.start && uri.end <= c.end),
        )
        .toList();
  }

  /// The files it names, written in [from], as absolute paths. URIs of other
  /// schemes and unknown packages are left out.
  List<String> pathsFrom(String from, PackageResolver packages) => [
    for (final uri in uris)
      if (packages.resolve(uri.namedGroup('uri')!, from)
          case final path? && != unknownPackage)
        path,
  ];
}

/// The library that the file at [path] belongs to: the file that its
/// `part of` directive names, through parts of parts, or [path] itself.
/// `null` when a directive names a library by its name, not its file, or when
/// the `part of` directives form a cycle, which doesn't compile.
String? libraryOf(String path, PackageResolver packages) {
  final seen = <String>{};
  for (String? file = path; file != null && seen.add(file);) {
    final partOf = _partDirectivesIn(
      file,
    ).firstWhereOrNull((directive) => directive.isPartOf);
    if (partOf == null) {
      return file;
    }
    file = partOf.pathsFrom(file, packages).firstOrNull;
  }
  return null;
}

/// The files of [library]: itself and its parts, through parts of parts.
Set<String> filesOfLibrary(String library, PackageResolver packages) =>
    reachableFrom(
      [library],
      (path) => [
        for (final directive in _partDirectivesIn(path))
          if (!directive.isPartOf) ...directive.pathsFrom(path, packages),
      ],
    );

/// The `part` and `part of` directives of the file at [path].
Iterable<Directive> _partDirectivesIn(String path) {
  final content = readSource(path) ?? '';
  // Only a file that may hold one is parsed: stripping comments is slow.
  if (!_maybePart.hasMatch(content)) {
    return const [];
  }
  return Directive.allIn(content).where((d) => d.keyword == 'part');
}

final _maybePart = RegExp(r'^[ \t]*part\b', multiLine: true);

/// Whether [content] has nothing but comments and `library`, `import` or
/// `part of` directives. An `export` or `part` directive counts as content: the
/// file passes something on. Reads only up to the first other token.
bool isDirectiveOnly(String content) {
  var i = skipCommentsAndWhitespace(content, 0);
  while (i < content.length) {
    switch (_skipInertDirective(content, i)) {
      case final end?:
        i = skipCommentsAndWhitespace(content, end);
      case null:
        return false;
    }
  }
  return true;
}

/// The index just past the inert directive at [from], or `null` when none
/// starts there. Inert ones pass nothing on: `library`, `import` and
/// `part of`, unlike `export` and `part`.
int? _skipInertDirective(String content, int from) {
  final keyword = _wordAt(content, from);
  final rest = skipCommentsAndWhitespace(content, from + keyword.length);
  final isInert = switch (keyword) {
    'library' => true,
    'import' =>
      rest < content.length && stringLiteralEnd(content, rest) != null,
    'part' => _wordAt(content, rest) == 'of',
    _ => false,
  };
  return isInert ? _statementEnd(content, rest) : null;
}

/// The index just past the first `;` at or after [from] outside comments and
/// strings, or `null` when there is none.
int? _statementEnd(String content, int from) {
  for (var i = skipCommentsAndWhitespace(content, from); i < content.length;) {
    if (content[i] == ';') {
      return i + 1;
    }
    i = skipCommentsAndWhitespace(
      content,
      stringLiteralEnd(content, i) ?? i + 1,
    );
  }
  return null;
}

/// The identifier at [from], or `''` when none starts there.
String _wordAt(String content, int from) =>
    _identifier.matchAsPrefix(content, from)?.group(0) ?? '';

final _identifier = RegExp(r'[A-Za-z_$][A-Za-z0-9_$]*');

final _directive = RegExp(
  r'^[ \t]*(?<keyword>import|export|part)\s+(?<body>[^;]*);',
  multiLine: true,
);

final _partOf = RegExp(r'^of\b');

/// The parenthesized condition of an `if` clause.
final _condition = RegExp(r'\bif\s*\([^)]*\)');
