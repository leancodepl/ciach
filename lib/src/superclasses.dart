import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location, Position;

/// Whether a class can lose all of its constructors. The implicit default
/// constructor that replaces them calls `super()`, which compiles only if the
/// superclass's unnamed constructor takes no required arguments.
final class SuperclassChecks {
  SuperclassChecks(this._client);

  final LspClient _client;

  /// Verdicts by superclass location.
  final _bySuperclass = <String, Future<bool>>{};

  /// Whether an implicit default constructor for [cls] would fail to compile.
  /// `true` when the superclass cannot be read.
  Future<bool> needsConstructorArguments(Candidate cls) async {
    final Location? superclass;
    try {
      superclass = await _client.superOf(
        cls.uri,
        cls.symbol.selectionRange.start,
      );
    } on Object {
      return true;
    }
    if (superclass == null) {
      return false;
    }
    final start = superclass.range.start;
    final key = '${superclass.uri}:${start.line}:${start.character}';
    return _bySuperclass.putIfAbsent(key, () => _needsArguments(superclass!));
  }

  Future<bool> _needsArguments(Location superclass) async {
    final uri = Uri.parse(superclass.uri);
    final List<DocumentSymbol> symbols;
    try {
      symbols = await _client.documentSymbol(uri);
    } on Object {
      return true;
    }
    final declaration = _symbolNamedAt(symbols, superclass.range.start);
    if (declaration == null) {
      return true;
    }
    final constructors = [
      if (declaration.children case final children?)
        for (final child in children)
          if (child.kind == .constructor) child,
    ];
    if (constructors.isEmpty) {
      return false;
    }
    // Constructor names include the class name.
    final unnamed = constructors.firstWhereOrNull(
      (c) => c.name == declaration.name,
    );
    if (unnamed == null) {
      return true;
    }
    return switch (parameterListShape(unnamed.detail)) {
      .none || .optionalPositional => false,
      .positional => true,
      .named => await _hasRequiredNamed(uri, unnamed),
    };
  }

  /// Whether [ctor] has a `required` named parameter, read from the `keyword`
  /// tokens so a parameter named `required` does not count. `true` when the
  /// file cannot be read.
  Future<bool> _hasRequiredNamed(Uri uri, DocumentSymbol ctor) async {
    final content = SourceIndex.readFile(uri.toFilePath());
    if (content == null) {
      return true;
    }
    final List<SemanticToken> tokens;
    try {
      tokens = await _client.semanticTokens(uri, content.split('\n'));
    } on Object {
      return true;
    }
    return tokens
        .between(ctor.range.start, ctor.range.end)
        .any((t) => t.isKeyword && t.text == 'required');
  }

  /// The symbol whose name starts at [position]. [symbols] are in source
  /// order, so the enclosing symbol at each level is the last one starting at
  /// or before [position].
  static DocumentSymbol? _symbolNamedAt(
    List<DocumentSymbol> symbols,
    Position position,
  ) {
    var lo = 0;
    var hi = symbols.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (symbols[mid].range.start.atOrBefore(position)) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    if (lo == 0 || !position.within(symbols[lo - 1])) {
      return null;
    }
    final symbol = symbols[lo - 1];
    if (symbol.selectionRange.start == position) {
      return symbol;
    }
    return switch (symbol.children) {
      final children? => _symbolNamedAt(children, position),
      _ => null,
    };
  }
}

/// The shape of a parameter list, decided by its first parameter. Required
/// positional parameters can only come first, followed by either optional
/// positional or named ones, so the first parameter tells whether a call
/// needs arguments.
enum ParameterListShape {
  /// `()`
  none,

  /// `(int x, …)`: a required positional parameter first, whatever follows.
  positional,

  /// `([int x, …])`: only optional positional parameters.
  optionalPositional,

  /// `({int x, …})`: only named parameters.
  named,
}

/// The shape of the parameter list a document symbol's [detail] spells out.
ParameterListShape parameterListShape(String? detail) {
  final trimmed = detail?.trim() ?? '';
  final inner = trimmed.startsWith('(') && trimmed.endsWith(')')
      ? trimmed.substring(1, trimmed.length - 1).trim()
      : trimmed;
  return switch (inner) {
    '' => .none,
    _ when inner.startsWith('[') => .optionalPositional,
    _ when inner.startsWith('{') => .named,
    _ => .positional,
  };
}
