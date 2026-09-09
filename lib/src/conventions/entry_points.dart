import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

/// A declaration a framework or tool calls by convention, with no source
/// reference for the search to find: a top-level name in a file.
///
/// That is the whole contract the callers apply themselves — flutter_tools
/// finds `flutter_test_config.dart` by name and generates a call to
/// `testExecutable` — so a rule is a name plus the files it lives in, nothing
/// about the declaration's shape. The compiler enforces the shape at the
/// generated call site.
final class EntryPoint {
  /// [name] is `name` or `Container.member`; [files] are POSIX globs relative
  /// to the package root, any of which may match (none means any file).
  EntryPoint({required this.name, required this.reason, this.files = const []})
    : _globs = [for (final file in files) Glob(file, context: _posix)];

  /// A rule from the `entry-points` config key.
  ///
  /// Throws a [FormatException] for a [name] that is not an identifier
  /// (optionally `Container.member`) or a glob that does not parse.
  factory EntryPoint.project(String name, {List<String> files = const []}) {
    if (!_qualifiedName.hasMatch(name)) {
      throw FormatException(
        "'$name' is not a declaration name; expected an identifier such as 'registerWith' or 'MyPlugin.registerWith'.",
      );
    }
    for (final file in files) {
      try {
        Glob(file, context: _posix);
      } on FormatException catch (e) {
        throw FormatException("'$file' is not a valid glob: ${e.message}");
      }
    }
    return EntryPoint(
      name: name,
      files: files,
      reason: 'listed under `entry-points` in the config file',
    );
  }

  static final _posix = p.Context(style: p.Style.posix);
  static final _qualifiedName = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?$',
  );

  /// `name` for a top-level declaration, `Container.member` for a member.
  final String name;

  /// The file globs as written; empty matches any file.
  final List<String> files;

  /// Who calls the declaration, for `--verbose`.
  final String reason;

  final List<Glob> _globs;

  /// The conventions applied on every run.
  static final builtIn = <EntryPoint>[
    EntryPoint(name: 'main', reason: 'the program entry point'),
    // `flutter test` generates an in-memory bootstrap that imports the nearest
    // `flutter_test_config.dart` and calls `testExecutable(testMain)`.
    EntryPoint(
      name: 'testExecutable',
      files: const ['**/flutter_test_config.dart'],
      reason: 'called by the `flutter test` bootstrap',
    ),
  ];

  /// Whether [symbol], in the file at [relativePath] (POSIX, from the package
  /// root) inside [container] (`null` at the top level), meets this rule.
  bool matches(String relativePath, DocumentSymbol symbol, String? container) {
    final qualified = container == null
        ? symbol.name
        : '$container.${symbol.name}';
    return qualified == name &&
        (_globs.isEmpty || _globs.any((glob) => glob.matches(relativePath)));
  }

  @override
  String toString() => files.isEmpty ? name : '$name in ${files.join(' or ')}';
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
