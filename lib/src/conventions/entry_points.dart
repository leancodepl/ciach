import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

/// A declaration a framework or tool calls by convention, with no source
/// reference for the search to find: a name in a file, the public methods of
/// a class's subclasses, or what an annotation marks.
///
/// That is the whole contract the callers apply themselves — flutter_tools
/// finds `flutter_test_config.dart` by name and generates a call to
/// `testExecutable` — so a rule says which declarations it matches and the
/// files they live in, nothing about the declaration's shape. The compiler enforces the shape at the
/// generated call site.
final class EntryPoint {
  /// [name] is `name` or `Container.member`; [files] are POSIX globs relative
  /// to the package root, any of which may match (none means any file).
  ///
  /// A glob that does not parse throws the glob package's [FormatException],
  /// whose `source` is the glob.
  EntryPoint({required this.name, required this.reason, this.files = const []})
    : superclass = null,
      annotation = null,
      annotationLibrary = null,
      _globs = [for (final file in files) .new(file, context: _posix)];

  /// Creates a rule that matches the public methods of every class that
  /// directly extends [superclass].
  EntryPoint.publicMethodsOfSubclasses(
    String this.superclass, {
    required this.reason,
    this.files = const [],
  }) : name = '*',
       annotation = null,
       annotationLibrary = null,
       _globs = [for (final file in files) .new(file, context: _posix)];

  /// Creates a rule that matches every declaration whose annotation calls a
  /// constructor of the class [annotation], or of a class that has
  /// [annotation] among its supertypes. [annotationLibrary], such as
  /// `package:flutter/src/widget_previews/widget_previews.dart`, is the
  /// library that declares the class; without it, a class of that name from
  /// any library counts.
  EntryPoint.annotatedWith(
    String this.annotation, {
    this.annotationLibrary,
    required this.reason,
    this.files = const [],
  }) : name = '*',
       superclass = null,
       _globs = [for (final file in files) .new(file, context: _posix)];

  /// Creates a rule that comes from the `entry-points` setting or from the
  /// project config.
  ///
  /// Name a constructor the way the report prints it, such as `Class.new` or
  /// `Class.named`.
  ///
  /// Throws a [FormatException] if [name] is not an identifier or
  /// `Container.member`, or if it is `Class.Class`. The constructor throws for
  /// a glob that does not parse.
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
    if (name.split('.') case [final type, final member] when member == type) {
      throw FormatException(
        "'$name' is not a valid name. Write the unnamed constructor as `$type.new`.",
      );
    }
    return .new(name: name, files: files, reason: reason);
  }

  /// Creates an [EntryPoint.annotatedWith] rule that comes from the
  /// `entry-points` setting.
  ///
  /// Throws a [FormatException] if [annotation] is not a class name. The
  /// constructor throws for a glob that does not parse.
  factory EntryPoint.annotationFromConfig(
    String annotation, {
    List<String> files = const [],
    String reason = 'listed under `entry-points` in the config file',
  }) {
    if (annotation.startsWith('@')) {
      throw FormatException(
        "'$annotation': write the class name without `@`, such as `${annotation.substring(1)}`.",
      );
    }
    if (!_identifier.hasMatch(annotation)) {
      throw FormatException(
        "'$annotation' is not a class name; expected an identifier such as 'Story'.",
      );
    }
    return .annotatedWith(annotation, files: files, reason: reason);
  }

  static final _posix = p.Context(style: .posix);
  static final _qualifiedName = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?$',
  );
  static final _identifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$');

  /// The name of the declaration. A top-level declaration is `name` and a
  /// member is `Container.member`. The unnamed constructor is `Class.new`.
  /// Type parameters are not part of the name.
  final String name;

  /// The superclass that a [EntryPoint.publicMethodsOfSubclasses] rule
  /// matches. It is `null` for every other rule.
  final String? superclass;

  /// The annotation class that an [EntryPoint.annotatedWith] rule matches. It
  /// is `null` for every other rule.
  final String? annotation;

  /// The library that declares the [annotation] class, or `null` for any
  /// library.
  final Uri? annotationLibrary;

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
    // `flutter widget-preview start` shows every function and constructor
    // whose annotation is a `Preview` or a `MultiPreview`, or a subclass of
    // either.
    for (final annotation in ['Preview', 'MultiPreview'])
      .annotatedWith(
        annotation,
        annotationLibrary: .parse(
          'package:flutter/src/widget_previews/widget_previews.dart',
        ),
        reason: 'shown by `flutter widget-preview`',
      ),
  ];

  /// Whether [symbol], in the file at [relativePath] (POSIX, from the package
  /// root) inside [container] (`null` at the top level), meets this rule.
  /// Returns whether this rule matches [symbol]. [containerSuperclass] is
  /// called only for a [superclass] rule, because it has to parse the source.
  /// [annotationTypes] holds the classes whose constructors the annotations of
  /// [symbol] call, and all of their supertypes.
  ///
  /// A rule that names a class or an extension type also matches the type's
  /// unnamed constructor, because code that uses the type calls `Type()`.
  /// Pass [inEnum] when [container] is an enum. Only the enum's own values
  /// call its constructor, so the rule does not match it.
  bool matches(
    String relativePath,
    DocumentSymbol symbol,
    String? container, {
    String? Function()? containerSuperclass,
    Set<AnnotationClass> annotationTypes = const {},
    bool inEnum = false,
  }) {
    final named = switch ((superclass, annotation)) {
      (final superclass?, _) =>
        container != null &&
            symbol.kind == .method &&
            !symbol.name.startsWith('_') &&
            containerSuperclass?.call() == superclass,
      (_, final annotation?) => annotationTypes.any(
        (type) =>
            type.name == annotation &&
            (annotationLibrary == null || type.library == annotationLibrary),
      ),
      _ => _namesDeclaration(symbol, container, inEnum: inEnum),
    };
    return named &&
        (_globs.isEmpty || _globs.any((glob) => glob.matches(relativePath)));
  }

  /// Whether [name] is the name of [symbol] inside [container], or names the
  /// type whose unnamed constructor [symbol] is.
  bool _namesDeclaration(
    DocumentSymbol symbol,
    String? container, {
    required bool inEnum,
  }) {
    final qualified =
        container?.let(
          (container) => '$container.${symbol.declarationName(container)}',
        ) ??
        symbol.name;
    return qualified == name ||
        (container == name &&
            !inEnum &&
            symbol.kind == .constructor &&
            symbol.declarationName(container) == 'new');
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
    return switch ((superclass, annotation)) {
      (final superclass?, _) => .publicMethodsOfSubclasses(
        superclass,
        reason: reason,
        files: scoped,
      ),
      (_, final annotation?) => .annotatedWith(
        annotation,
        annotationLibrary: annotationLibrary,
        reason: reason,
        files: scoped,
      ),
      _ => .new(name: name, reason: reason, files: scoped),
    };
  }

  /// The text that shows the rule to the user. It is the [name] of the rule,
  /// or, for a [superclass] or an [annotation] rule, a description of what
  /// the rule matches.
  String get label => switch ((superclass, annotation)) {
    (final superclass?, _) => 'public methods of `$superclass` subclasses',
    (_, final annotation?) =>
      'declarations annotated with `@$annotation` or a subclass of it',
    _ => name,
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
    Set<AnnotationClass> annotationTypes = const {},
    bool inEnum = false,
  }) => _rules.firstWhereOrNull(
    (rule) => rule.matches(
      relativePath,
      symbol,
      container,
      containerSuperclass: containerSuperclass,
      annotationTypes: annotationTypes,
      inEnum: inEnum,
    ),
  );
}

/// The class whose constructor an annotation calls, or one of its supertypes.
final class AnnotationClass {
  const AnnotationClass(this.name, this.library);

  final String name;

  /// The library that declares the class, such as
  /// `package:flutter/src/widget_previews/widget_previews.dart`, or `null`
  /// for a class outside every package, such as `Object`.
  final Uri? library;

  @override
  bool operator ==(Object other) =>
      other is AnnotationClass &&
      other.name == name &&
      other.library == library;

  @override
  int get hashCode => Object.hash(name, library);
}
