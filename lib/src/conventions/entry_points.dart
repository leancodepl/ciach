import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, SymbolKind;

/// The one parameter `flutter test`'s bootstrap passes to `testExecutable`: the
/// test file's `main`, typed `FutureOr<void> Function()`.
final _testMainParameter = RegExp(
  r'^\(\s*FutureOr<void>\s+Function\(\)\s+[A-Za-z_$][A-Za-z0-9_$]*\s*\)$',
);

/// A declaration a framework or tool invokes by convention, so that no source
/// in the package ever references it.
///
/// The reference search cannot see such a call, so the declaration would read
/// as dead. Each rule spells out the full contract the caller relies on — the
/// file the declaration must live in, its name, and where the caller is picky,
/// its kind and signature — and only a declaration meeting all of it is exempt.
/// A same-named function elsewhere, or one with a shape the caller could not
/// invoke, is still reported.
///
/// [builtIn] lists the conventions ciach knows; [EntryPoint.parse] builds one
/// from the `--entry-point` / `entry-point:` spec a project adds for its own.
final class EntryPoint {
  /// Creates a rule matching a declaration named [name] — `name` for a
  /// top-level declaration, `Container.member` for a member — in files matching
  /// the POSIX glob [file] (relative to the package root; `null` for any file),
  /// of kind [kind] (`null` for any) whose LSP `detail` (the parameter list)
  /// satisfies [signature] (`null` for any). [reason] says who calls it.
  EntryPoint({
    required this.name,
    required this.reason,
    String? file,
    this.kind,
    RegExp? signature,
  }) : filePattern = file,
       _file = file == null ? null : Glob(file, context: _posix),
       _signature = signature;

  /// Parses a `<file glob>:<name>` or bare `<name>` spec, as given on the
  /// command line or in the config file, into a rule that matches on file and
  /// name alone (any kind, any signature).
  ///
  /// The last `:` separates the two, so a glob may not contain one. Throws a
  /// [FormatException] naming the problem for an empty name, an invalid glob,
  /// or a name that is not a Dart identifier (optionally `Container.member`).
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

  /// The declaration name: `name` for a top-level one, `Container.member` for
  /// a member.
  final String name;

  /// The file glob as written, for display; `null` matches any file.
  final String? filePattern;

  /// Who invokes the declaration, for `--verbose`.
  final String reason;

  /// The kind the declaration must have, or `null` for any.
  final SymbolKind? kind;

  final Glob? _file;
  final RegExp? _signature;

  /// The conventions ciach applies on every run.
  static final builtIn = <EntryPoint>[
    // The program's entry point, in every file that has one: a `bin/` script, a
    // test, an example.
    EntryPoint(
      name: 'main',
      kind: .function,
      reason: 'the program entry point',
    ),
    // `flutter test` walks up from each test file to the nearest
    // `flutter_test_config.dart` and generates a bootstrap that imports it and
    // calls `testExecutable(testMain)`. The bootstrap never lands on disk, so
    // the call is invisible to the reference search.
    EntryPoint(
      name: 'testExecutable',
      file: '**/flutter_test_config.dart',
      kind: .function,
      signature: _testMainParameter,
      reason: 'called by the `flutter test` bootstrap',
    ),
  ];

  /// Whether [symbol], declared in the file at [relativePath] (POSIX, relative
  /// to the package root) inside [container] (`null` at the top level), meets
  /// this rule's whole contract.
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

  /// The spec form of this rule, as `--entry-point` would take it.
  @override
  String toString() => filePattern == null ? name : '$filePattern:$name';
}

/// The built-in conventions followed by a project's own rules.
///
/// A declaration is matched against every rule in turn and the first hit wins;
/// the order only decides which [EntryPoint.reason] `--verbose` shows.
final class EntryPoints {
  /// Creates the rule set: [EntryPoint.builtIn] plus [extra].
  EntryPoints(List<EntryPoint> extra)
    : _rules = [...EntryPoint.builtIn, ...extra];

  final List<EntryPoint> _rules;

  /// The first rule [symbol] satisfies, or `null` when it is an ordinary
  /// declaration. See [EntryPoint.matches] for the arguments.
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
