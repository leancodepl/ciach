import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/conventions/test_reflective_loader.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:collection/collection.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol;

part 'annotation_name_entry_point.dart';
part 'named_entry_point.dart';
part 'subtype_entry_point.dart';

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

  static const _configReason = 'listed under `entry-points` in the config file';
  static final _posix = p.Context(style: .posix);
  static final _qualifiedName = RegExp(
    r'^[A-Za-z_$][A-Za-z0-9_$]*(?:\.[A-Za-z_$][A-Za-z0-9_$]*)?$',
  );

  /// The file globs as written; empty matches any file.
  final List<String> files;

  /// Who calls what the rule selects, for `--verbose`, or `null` when the
  /// rule keeps only the [members] of a type that it selects, as the rule for
  /// `@reflectiveTest` does.
  String? get reason;

  /// The members that the rule keeps in a type that it selects, or `null`
  /// for none.
  KeptMembers? get members => null;

  /// The requests that the analysis server has to answer before the rule can
  /// select a declaration.
  Set<ServerLookup> get lookups => const {};

  /// The names after the `@` whose declaring package the analysis server has
  /// to give before the rule can select a declaration.
  Set<String> get annotationNames => const {};

  final List<Glob> _globs;

  /// The conventions applied on every run.
  static final List<EntryPoint> builtIn = [
    .new(name: 'main', reason: 'the program entry point'),
    // `flutter test` generates an in-memory bootstrap that imports the nearest
    // `flutter_test_config.dart` and calls `testExecutable(testMain)`.
    .new(
      name: 'testExecutable',
      files: const ['**/flutter_test_config.dart'],
      reason: 'called by the `flutter test` bootstrap',
    ),
    // Dart 3.10 declares `JSExport` in `dart:_js_annotations`, which
    // `dart:js_interop` exports. `package:js` 0.6 declares its own.
    AnnotationNameEntryPoint(
      'JSExport',
      packages: const {'dart:js_interop', 'dart:_js_annotations', 'js'},
      reason: 'exported to JavaScript by `@JSExport`',
      members: const .new(
        .publicMembers,
        'exported to JavaScript by `@JSExport` on its class',
      ),
    ),
    // The other values of `pragma`, such as `vm:prefer-inline`, keep nothing.
    AnnotationNameEntryPoint(
      'pragma',
      packages: const {'dart:core'},
      argument: 'vm:entry-point',
      reason:
          "marked `@pragma('vm:entry-point')` for native code or reflection",
    ),
    AnnotationNameEntryPoint(
      'reflectiveTest',
      packages: const {'test_reflective_loader'},
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

/// A kind of request that a rule needs the analysis server to answer before
/// it can select a declaration.
enum ServerLookup {
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

  /// Returns the requests that the analysis server has to answer in the file
  /// at [relativePath] for the rules that apply to it.
  Set<ServerLookup> lookupsIn(String relativePath) => {
    for (final rule in _rules)
      if (rule.appliesTo(relativePath)) ...rule.lookups,
  };

  /// Returns the names after the `@` whose declaring package the analysis
  /// server has to give in the file at [relativePath] for the rules that
  /// apply to it.
  Set<String> annotationNamesIn(String relativePath) => {
    for (final rule in _rules)
      if (rule.appliesTo(relativePath)) ...rule.annotationNames,
  };
}
