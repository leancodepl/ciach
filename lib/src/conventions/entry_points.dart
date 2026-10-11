import 'package:collection/collection.dart';
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
  ///
  /// A glob that does not parse throws the glob package's [FormatException],
  /// whose `source` is the glob.
  EntryPoint({required this.name, required this.reason, this.files = const []})
    : superclass = null,
      _globs = [for (final file in files) .new(file, context: _posix)];

  /// Creates a rule that matches the public methods of every class that
  /// directly extends [superclass].
  EntryPoint.publicMethodsOfSubclasses(
    String this.superclass, {
    required this.reason,
    this.files = const [],
  }) : name = '*',
       _globs = [for (final file in files) .new(file, context: _posix)];

  /// Creates a rule that comes from the `entry-points` setting or from the
  /// project config.
  ///
  /// Throws a [FormatException] for a [name] that is not an identifier
  /// (optionally `Container.member`); the constructor throws for a glob that
  /// does not parse.
  factory EntryPoint.fromConfig(
    String name, {
    List<String> files = const [],
    String reason = 'listed under `entry-points` in the config file',
  }) {
    if (name.contains('<')) {
      throw FormatException(
        "'$name': type parameters are not part of a declaration name; write `MyClass.member`, not `MyClass<T>.member`.",
      );
    }
    if (!_qualifiedName.hasMatch(name)) {
      throw FormatException(
        "'$name' is not a declaration name; expected an identifier such as 'registerWith' or 'MyPlugin.registerWith'.",
      );
    }
    return .new(name: name, files: files, reason: reason);
  }

  static final _posix = p.Context(style: .posix);
  static final _qualifiedName = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?$',
  );

  /// `name` for a top-level declaration, `Container.member` for a member;
  /// type parameters are not part of either.
  final String name;

  /// The superclass that a [EntryPoint.publicMethodsOfSubclasses] rule
  /// matches. It is `null` for every other rule.
  final String? superclass;

  /// The file globs as written; empty matches any file.
  final List<String> files;

  /// Who calls the declaration, for `--verbose`.
  final String reason;

  final List<Glob> _globs;

  /// The conventions applied on every run.
  static final builtIn = <EntryPoint>[
    .new(name: 'main', reason: 'the program entry point'),
    // `flutter test` generates an in-memory bootstrap that imports the nearest
    // `flutter_test_config.dart` and calls `testExecutable(testMain)`.
    .new(
      name: 'testExecutable',
      files: const ['**/flutter_test_config.dart'],
      reason: 'called by the `flutter test` bootstrap',
    ),
  ];

  /// Whether [symbol], in the file at [relativePath] (POSIX, from the package
  /// root) inside [container] (`null` at the top level), meets this rule.
  /// Returns whether this rule matches [symbol]. [containerSuperclass] is
  /// called only for a [superclass] rule, because it has to parse the source.
  bool matches(
    String relativePath,
    DocumentSymbol symbol,
    String? container, {
    String? Function()? containerSuperclass,
  }) {
    final bool named;
    if (superclass case final superclass?) {
      named =
          container != null &&
          symbol.kind == .method &&
          !symbol.name.startsWith('_') &&
          containerSuperclass?.call() == superclass;
    } else {
      final qualified = container == null
          ? symbol.name
          : '$container.${symbol.name}';
      named = qualified == name;
    }
    return named &&
        (_globs.isEmpty || _globs.any((glob) => glob.matches(relativePath)));
  }

  /// Returns this rule, limited to the package in the directory [prefix].
  /// [prefix] is relative to the scanned root and is escaped as a glob. An
  /// empty [prefix] means the scanned root itself.
  EntryPoint within(String prefix) {
    if (prefix.isEmpty) {
      return this;
    }
    final scoped = files.isEmpty
        ? ['$prefix/**']
        : [for (final file in files) '$prefix/$file'];
    return switch (superclass) {
      final superclass? => .publicMethodsOfSubclasses(
        superclass,
        reason: reason,
        files: scoped,
      ),
      null => .new(name: name, reason: reason, files: scoped),
    };
  }

  /// The text that shows the rule to the user. It is the [name] of the rule,
  /// or, for a [superclass] rule, a description of what the rule matches.
  String get label => switch (superclass) {
    final superclass? => 'public methods of `$superclass` subclasses',
    null => name,
  };

  @override
  String toString() =>
      files.isEmpty ? label : '$label in ${files.join(' or ')}';
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
    String? container, {
    String? Function()? containerSuperclass,
  }) => _rules.firstWhereOrNull(
    (rule) => rule.matches(
      relativePath,
      symbol,
      container,
      containerSuperclass: containerSuperclass,
    ),
  );
}
