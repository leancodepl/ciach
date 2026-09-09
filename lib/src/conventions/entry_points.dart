import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, SymbolKind;

/// The one parameter the `flutter test` bootstrap passes: the test's `main`.
final _testMainParameter = RegExp(
  r'^\(\s*FutureOr<void>\s+Function\(\)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\)$',
);

/// A declaration a framework or tool calls by convention, with no source
/// reference for the search to find.
///
/// A rule spells out the caller's contract — file, name, and where it matters,
/// kind and signature — and exempts only a declaration meeting all of it.
final class EntryPoint {
  /// [name] is `name` or `Container.member`; [file] a POSIX glob relative to
  /// the package root (`null` for any file); [signature] matches the LSP
  /// `detail`, i.e. the parameter list. [reason] says who calls it.
  EntryPoint({
    required this.name,
    required this.reason,
    String? file,
    this.kind,
    RegExp? signature,
  }) : filePattern = file,
       _file = file == null ? null : Glob(file, context: _posix),
       _signature = signature;

  /// Parses a `<file glob>:<name>` or bare `<name>` spec (the last `:` splits
  /// them) into a rule matching on file and name alone.
  ///
  /// Throws a [FormatException] for an empty name or glob, a name that is not
  /// an identifier (optionally `Container.member`), or an invalid glob.
  factory EntryPoint.parse(String spec) {
    final trimmed = spec.trim();
    final colon = trimmed.lastIndexOf(':');
    final file = colon < 0 ? null : trimmed.substring(0, colon).trim();
    final name = colon < 0 ? trimmed : trimmed.substring(colon + 1).trim();
    if (name.isEmpty) {
      throw FormatException(
        "Entry point '$spec' names no declaration; expected '<file glob>:<name>' or '<name>'.",
      );
    }
    if (!_qualifiedName.hasMatch(name)) {
      throw FormatException(
        "Entry point '$spec': '$name' is not a declaration name; expected an identifier such as 'registerWith' or 'MyPlugin.registerWith'.",
      );
    }
    if (file != null && file.isEmpty) {
      throw FormatException(
        "Entry point '$spec' has an empty file glob; drop the ':' to match any file.",
      );
    }
    try {
      return EntryPoint(
        name: name,
        file: file,
        reason: 'listed as an entry point by this project',
      );
    } on FormatException catch (e) {
      throw FormatException(
        "Entry point '$spec': '$file' is not a valid glob: ${e.message}",
      );
    }
  }

  static final _posix = p.Context(style: p.Style.posix);
  static final _qualifiedName = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?$',
  );

  /// `name` for a top-level declaration, `Container.member` for a member.
  final String name;

  /// The file glob as written; `null` matches any file.
  final String? filePattern;

  /// Who calls the declaration, for `--verbose`.
  final String reason;

  /// The required kind, or `null` for any.
  final SymbolKind? kind;

  final Glob? _file;
  final RegExp? _signature;

  /// The conventions applied on every run.
  static final builtIn = <EntryPoint>[
    EntryPoint(
      name: 'main',
      kind: .function,
      reason: 'the program entry point',
    ),
    // `flutter test` generates an in-memory bootstrap that imports the nearest
    // `flutter_test_config.dart` and calls `testExecutable(testMain)`.
    EntryPoint(
      name: 'testExecutable',
      file: '**/flutter_test_config.dart',
      kind: .function,
      signature: _testMainParameter,
      reason: 'called by the `flutter test` bootstrap',
    ),
  ];

  /// Whether [symbol], in the file at [relativePath] (POSIX, from the package
  /// root) inside [container] (`null` at the top level), meets this rule.
  bool matches(String relativePath, DocumentSymbol symbol, String? container) {
    final qualified = container == null
        ? symbol.name
        : '$container.${symbol.name}';
    if (qualified != name) {
      return false;
    }
    if (kind != null && symbol.kind != kind) {
      return false;
    }
    if (_file case final glob? when !glob.matches(relativePath)) {
      return false;
    }
    if (_signature case final signature?
        when !signature.hasMatch(symbol.detail?.trim() ?? '')) {
      return false;
    }
    return true;
  }

  /// The spec form, as `--entry-point` takes it.
  @override
  String toString() => filePattern == null ? name : '$filePattern:$name';
}

/// [EntryPoint.builtIn] followed by a project's own rules; the first match
/// wins.
final class EntryPoints {
  EntryPoints(List<EntryPoint> extra)
    : _rules = [...EntryPoint.builtIn, ...extra];

  final List<EntryPoint> _rules;

  /// The first rule [symbol] meets, or `null` for an ordinary declaration.
  EntryPoint? match(
    String relativePath,
    DocumentSymbol symbol,
    String? container,
  ) {
    for (final rule in _rules) {
      if (rule.matches(relativePath, symbol, container)) {
        return rule;
      }
    }
    return null;
  }
}
