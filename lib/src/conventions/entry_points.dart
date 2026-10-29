import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/conventions/test_reflective_loader.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

/// A declaration a framework or tool calls by convention, with no source
/// reference for the search to find.
///
/// A rule selects declarations by their name, by an annotation or by a
/// supertype, in the files it lives in. It keeps what it selects, and for a
/// type, it may keep some of the type's members too. That is the whole
/// contract the callers apply themselves — flutter_tools finds
/// `flutter_test_config.dart` by name and generates a call to
/// `testExecutable` — so a rule says nothing about the declaration's shape.
/// The compiler enforces the shape at the generated call site.
sealed class EntryPoint {
  /// Creates a rule that selects the declaration called [name], which is
  /// `name` or `Container.member`. [files] are POSIX globs relative to the
  /// package root, any of which may match (none means any file).
  ///
  /// A glob that does not parse throws the glob package's [FormatException],
  /// whose `source` is the glob.
  factory EntryPoint({
    required String name,
    required String reason,
    List<String> files,
  }) = NamedEntryPoint;

  EntryPoint._({required this.files})
    : _globs = [for (final file in files) .new(file, context: _posix)];

  /// Creates a rule that selects every class that has [superclass], from
  /// [package] or from any package when it is `null`, among its supertypes,
  /// and keeps the public methods of the class too. [reason] says who calls
  /// the methods.
  factory EntryPoint.publicMethodsOfSubclasses(
    String superclass, {
    String? package,
    required String reason,
    List<String> files,
  }) = SubtypeEntryPoint;

  /// Creates a rule that selects every declaration whose annotation creates
  /// an object of the class [annotation], from [package] or from any package
  /// when it is `null`.
  ///
  /// Unless [subtypes] is `false`, an object of a subtype of the class
  /// counts too. Unless [constants] is `false`, an annotation that reads a
  /// constant, such as `@story` for `const story = Story();`, counts too;
  /// with it, only a constructor call counts.
  factory EntryPoint.annotatedWith(
    String annotation, {
    String? package,
    bool? subtypes,
    bool? constants,
    required String reason,
    List<String> files,
  }) = AnnotatedEntryPoint;

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
    String reason = _configReason,
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
  /// Throws a [FormatException] if [annotation] is not a class name or
  /// [package] is not a package name. The constructor throws for a glob that
  /// does not parse.
  factory EntryPoint.annotationFromConfig(
    String annotation, {
    String? package,
    bool? subtypes,
    bool? constants,
    List<String> files = const [],
    String reason = _configReason,
  }) {
    if (annotation.startsWith('@')) {
      throw FormatException(
        "'$annotation': write the class name without `@`, such as `${annotation.substring(1)}`.",
      );
    }
    if (annotation.contains('.') || !_qualifiedName.hasMatch(annotation)) {
      throw FormatException(
        "'$annotation' is not a class name; expected an identifier such as 'Story'.",
      );
    }
    if (package != null && !_packageName.hasMatch(package)) {
      throw FormatException(
        "'$package' is not a package name; expected a name such as 'storybook', without `package:`.",
      );
    }
    return .annotatedWith(
      annotation,
      package: package,
      subtypes: subtypes,
      constants: constants,
      files: files,
      reason: reason,
    );
  }

  static const _configReason = 'listed under `entry-points` in the config file';
  static final _posix = p.Context(style: .posix);
  static final _qualifiedName = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?$',
  );
  static final _packageName = RegExp(r'^[a-z_][a-z0-9_]*$');

  /// The file globs as written; empty matches any file.
  final List<String> files;

  /// Who calls what the rule selects, for `--verbose`, or `null` when the
  /// rule keeps only the [members] of a type that it selects, as the rule for
  /// `@reflectiveTest` does.
  String? get reason;

  /// The members that the rule keeps in a type that it selects, or `null`
  /// for none.
  KeptMembers? get members => null;

  /// What the analysis server has to resolve for the rule to select a
  /// declaration.
  Set<ResolvedFact> get resolves => const {};

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
    // `JSExport` from `dart:js_interop` is a final class, and the older one
    // from `package:js` has no subclasses either, so the name is enough.
    AnnotationNameEntryPoint(
      'JSExport',
      reason: 'exported to JavaScript by `@JSExport`',
      members: const .new(
        .publicMembers,
        'exported to JavaScript by `@JSExport` on its class',
      ),
    ),
    AnnotationNameEntryPoint(
      'reflectiveTest',
      members: const .new(
        .reflectiveTestMethods,
        'run by `defineReflectiveTests`',
      ),
    ),
  ];

  /// Whether this rule selects [declaration].
  bool _selects(ResolvedDeclaration declaration);

  /// Returns this rule, with [files] in place of its globs.
  EntryPoint _withFiles(List<String> files);

  /// The text that shows what the rule selects to the user.
  String get label;

  /// Whether this rule applies to the file at [relativePath], POSIX and
  /// relative to the package root.
  bool appliesTo(String relativePath) =>
      _globs.isEmpty || _globs.any((glob) => glob.matches(relativePath));

  /// Whether this rule selects [declaration] in a file that it applies to.
  bool matches(ResolvedDeclaration declaration) =>
      _selects(declaration) && appliesTo(declaration.relativePath);

  /// Why [declaration], which this rule matches, is kept, for `--verbose`,
  /// or `null` when the rule doesn't keep it.
  String? reasonFor(ResolvedDeclaration declaration) => reason;

  /// Why the type that declares [qualified], which this rule matches, is
  /// kept, for `--verbose`.
  String containerReason(String qualified) =>
      'declares the entry point $qualified';

  /// Returns this rule, limited to the package in the directory [prefix].
  /// [prefix] is relative to the scanned root and is escaped as a glob. An
  /// empty [prefix] means the scanned root itself.
  EntryPoint within(String prefix) => prefix.isEmpty
      ? this
      : _withFiles(
          files.isEmpty
              ? ['$prefix/**']
              : [for (final file in files) '$prefix/$file'],
        );

  @override
  String toString() =>
      files.isEmpty ? label : '$label in ${files.join(' or ')}';
}

/// A rule that selects a declaration by its name.
final class NamedEntryPoint extends EntryPoint {
  NamedEntryPoint({
    required this.name,
    required this.reason,
    super.files = const [],
  }) : super._();

  @override
  final String reason;

  /// The name of the declaration. A top-level declaration is `name` and a
  /// member is `Container.member`. The unnamed constructor is `Class.new`.
  /// Type parameters are not part of the name.
  final String name;

  /// A rule that names a class or an extension type also selects the type's
  /// unnamed constructor, because code that uses the type calls `Type()`.
  /// Only an enum's own values call its constructor, so the rule does not
  /// select it in an enum.
  @override
  bool _selects(ResolvedDeclaration declaration) {
    final ResolvedDeclaration(:symbol, :container) = declaration;
    return declaration.qualifiedName == name ||
        (container == name &&
            !declaration.inEnum &&
            symbol.kind == .constructor &&
            symbol.declarationName(container) == 'new');
  }

  @override
  String reasonFor(ResolvedDeclaration declaration) =>
      declaration.container == name
      ? 'the unnamed constructor of the entry point $name'
      : reason;

  @override
  String containerReason(String qualified) => 'declares the entry point $name';

  @override
  NamedEntryPoint _withFiles(List<String> files) =>
      .new(name: name, reason: reason, files: files);

  @override
  String get label => name;
}

/// A rule that selects a declaration by the class of an annotation on it.
final class AnnotatedEntryPoint extends EntryPoint {
  AnnotatedEntryPoint(
    this.annotation, {
    this.package,
    bool? subtypes,
    bool? constants,
    required this.reason,
    super.files = const [],
  }) : subtypes = subtypes ?? true,
       constants = constants ?? true,
       super._();

  @override
  final String reason;

  /// The class of the annotation.
  final String annotation;

  /// The package that declares [annotation], or `null` for any package.
  final String? package;

  /// Whether an annotation whose class is a subtype of [annotation] counts.
  final bool subtypes;

  /// Whether an annotation that reads a constant counts.
  final bool constants;

  @override
  Set<ResolvedFact> get resolves => {
    .annotationClasses,
    if (constants) .constantClasses,
  };

  @override
  bool _selects(ResolvedDeclaration declaration) => declaration.annotations.any(
    (it) =>
        (constants || !it.readsConstant) &&
        (it.type.isNamed(annotation, package: package) ||
            (subtypes &&
                it.supertypes.any(
                  (type) => type.isNamed(annotation, package: package),
                ))),
  );

  @override
  AnnotatedEntryPoint _withFiles(List<String> files) => .new(
    annotation,
    package: package,
    subtypes: subtypes,
    constants: constants,
    reason: reason,
    files: files,
  );

  @override
  String get label => [
    'declarations annotated with `@$annotation`',
    if (package case final package?) 'from `package:$package`',
    if (subtypes) 'or a subtype of it',
    if (!constants) 'by a constructor call',
  ].join(' ');
}

/// A rule that selects a declaration by the name written in an annotation on
/// it, such as `JSExport` in `@JSExport()` and `reflectiveTest` in
/// `@reflectiveTest`, whatever it resolves to. It needs no requests to the
/// analysis server.
final class AnnotationNameEntryPoint extends EntryPoint {
  AnnotationNameEntryPoint(
    this.annotation, {
    this.reason,
    this.members,
    super.files = const [],
  }) : super._();

  /// The name written after the `@`.
  final String annotation;

  @override
  final String? reason;

  @override
  final KeptMembers? members;

  @override
  bool _selects(ResolvedDeclaration declaration) => declaration.leadingMetadata
      .any((token) => token.isAnnotationNamed(annotation));

  @override
  AnnotationNameEntryPoint _withFiles(List<String> files) =>
      .new(annotation, reason: reason, members: members, files: files);

  @override
  String get label => 'declarations annotated with `@$annotation`';
}

/// A rule that selects a class by one of its supertypes, and keeps the class
/// and its public methods.
final class SubtypeEntryPoint extends EntryPoint {
  /// [reason] says who calls the public methods.
  SubtypeEntryPoint(
    this.supertype, {
    this.package,
    required String reason,
    super.files = const [],
  }) : members = .new(.publicMethods, reason),
       super._();

  /// The supertype.
  final String supertype;

  /// The package that declares [supertype], or `null` for any package.
  final String? package;

  @override
  final KeptMembers members;

  @override
  String get reason =>
      'has `$supertype` among its supertypes, so its public methods are entry points';

  @override
  Set<ResolvedFact> get resolves => const {.supertypes};

  @override
  bool _selects(ResolvedDeclaration declaration) => declaration.supertypes.any(
    (type) => type.isNamed(supertype, package: package),
  );

  @override
  SubtypeEntryPoint _withFiles(List<String> files) =>
      .new(supertype, package: package, reason: members.reason, files: files);

  @override
  String get label => 'public methods of `$supertype` subclasses';
}

/// The members of a type that a rule keeps when it selects the type, and
/// who calls them.
final class KeptMembers {
  const KeptMembers(this.selection, this.reason);

  final MemberSelection selection;

  /// Who calls the members, for `--verbose`.
  final String reason;
}

/// Which members of a type a rule keeps.
enum MemberSelection {
  /// The public methods, which Serverpod's dispatcher calls.
  publicMethods,

  /// The public members other than constructors, which `@JSExport` on a class
  /// exports to JavaScript.
  publicMembers,

  /// The methods that `defineReflectiveTests` runs, such as `test_parses` and
  /// `setUp`.
  reflectiveTestMethods;

  /// Whether [member] is one of the selected members.
  bool includes(DocumentSymbol member) =>
      !isPrivateName(member.name) &&
      switch (this) {
        publicMethods => member.kind == .method,
        publicMembers => member.kind != .constructor,
        reflectiveTestMethods =>
          member.kind == .method && isReflectiveTestMethod(member.name),
      };
}

/// What the analysis server resolves for a rule to select a declaration.
enum ResolvedFact {
  /// The class that an annotation's constructor call creates, and its
  /// supertypes.
  annotationClasses,

  /// The class of the object that the constant an annotation reads holds,
  /// and its supertypes.
  constantClasses,

  /// The supertypes of a class.
  supertypes,
}

/// [EntryPoint.builtIn] followed by a project's own rules; the first match
/// wins.
final class EntryPoints {
  EntryPoints(List<EntryPoint> extra)
    : _rules = [...EntryPoint.builtIn, ...extra];

  final List<EntryPoint> _rules;

  /// The first rule that keeps [declaration], or `null` for an ordinary
  /// declaration.
  EntryPoint? match(ResolvedDeclaration declaration) => _rules.firstWhereOrNull(
    (rule) => rule.reason != null && rule.matches(declaration),
  );

  /// The members that the rules keep in [type].
  List<KeptMembers> keptMembersOf(ResolvedDeclaration type) => [
    for (final rule in _rules)
      if (rule.members case final members? when rule.matches(type)) members,
  ];

  /// What the analysis server has to resolve in the file at [relativePath]
  /// for the rules that apply to it.
  Set<ResolvedFact> resolvedIn(String relativePath) => {
    for (final rule in _rules)
      if (rule.appliesTo(relativePath)) ...rule.resolves,
  };
}
