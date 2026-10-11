import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/packages.dart';

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
    return [
      for (final uri in uriLiteral.allMatches(body))
        if (!conditions.any((c) => c.start <= uri.start && uri.end <= c.end))
          uri,
    ];
  }

  /// The files it names, written in [from], as absolute paths. URIs of other
  /// schemes and unknown packages are left out.
  List<String> pathsFrom(String from, PackageResolver packages) => [
    for (final uri in uris)
      if (packages.resolve(uri.namedGroup('uri')!, from) case final path?
          when path != unknownPackage)
        path,
  ];
}

final _directive = RegExp(
  r'^[ \t]*(?<keyword>import|export|part)\s+(?<body>[^;]*);',
  multiLine: true,
);

final _partOf = RegExp(r'^of\b');

/// The parenthesized condition of an `if` clause.
final _condition = RegExp(r'\bif\s*\([^)]*\)');
