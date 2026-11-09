/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:ciach/src/analysis/comments.dart';
import 'package:ciach/src/analysis/declaration_annotation.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/analysis/reference_index.dart';
import 'package:ciach/src/analysis/reference_shapes.dart' as shapes;
import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/analysis/type_hierarchy.dart';
import 'package:ciach/src/analysis/unit_outline.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/outline.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;

/// The cause of a problem with a file that [ResolvedFiles.of] doesn't
/// resolve.
const unresolvedFile = 'The analyzer could not resolve the file.';

/// The Dart files under an analysis root, and the files that they import, as
/// `package:analyzer` resolves them in this process.
final class ResolvedFiles implements FileSyntax {
  /// Creates the analysis of the Dart files under [root], an absolute and
  /// normalized path, with the Dart SDK at [sdkPath]. A file is resolved when
  /// it is first asked for.
  ResolvedFiles(String root, {required String sdkPath})
    : _collection = .new(includedPaths: [root], sdkPath: sdkPath);

  final AnalysisContextCollection _collection;
  final _packages = PackageResolver();
  late final _files = CachedMap<String, Future<ResolvedFile?>>(_resolve);
  late final _parsed = CachedMap<String, ParsedUnitResult?>(_parse);
  final _hierarchy = TypeHierarchy();
  late final _index = ReferenceIndex(_hierarchy);

  /// The files resolved so far, by path.
  final _resolved = <String, ResolvedFile>{};

  /// The element that each declaration of a resolved file declares, by the
  /// file's path and the start of the declaration's name.
  final _elements = <String, Map<Position, Element>>{};

  /// Returns the file at [path], an absolute and normalized path, or `null`
  /// when the analyzer can't read or resolve it, such as a file whose path
  /// isn't the path of its URI.
  Future<ResolvedFile?> of(String path) => _files[path];

  /// Returns the file at [path] when [of] has resolved it already.
  ResolvedFile? resolved(String path) => _resolved[path];

  @override
  bool isDocReference(Location location) =>
      _at(location.path, location.range.start, shapes.isDocReferenceAt) ??
      false;

  @override
  bool isTypePattern(Location location) =>
      _at(location.path, location.range.start, shapes.isTypePatternAt) ?? false;

  @override
  bool isEnumValuesAccess(Location location) =>
      _at(location.path, location.range.start, shapes.isEnumValuesAccessAt) ??
      false;

  @override
  bool isStateTypeArgument(Location location) =>
      _at(location.path, location.range.start, shapes.isStateTypeArgumentAt) ??
      false;

  @override
  ({Clause clause, Range entry})? clauseAt(Location location, String name) =>
      _at(
        location.path,
        location.range.start,
        (unit, offset) => shapes.clauseAt(unit, offset, name),
      );

  @override
  ({VariableStatement statement, Range declarator})? declaratorAt(
    String path,
    Position name,
  ) => _at(path, name, shapes.declaratorAt);

  @override
  bool isInBody(String path, Position position, Range declaration) =>
      _at(path, position, (unit, offset) {
        final lineInfo = unit.lineInfo;
        return switch ((
          lineInfo.offsetOf(declaration.start),
          lineInfo.offsetOf(declaration.end),
        )) {
          (final start?, final end?) => shapes.isInBodyAt(
            unit,
            offset,
            start,
            end,
          ),
          _ => false,
        };
      }) ??
      false;

  /// Returns what [read] reads at [position] in the parsed file at [path], or
  /// `null` when the file can't be parsed or [position] isn't in it.
  T? _at<T extends Object>(
    String path,
    Position position,
    T? Function(CompilationUnit unit, int offset) read,
  ) {
    final unit = _parsed[path]?.unit;
    final offset = unit?.lineInfo.offsetOf(position);
    return unit == null || offset == null ? null : read(unit, offset);
  }

  /// Resolves the Dart files that the analysis root's `analysis_options.yaml`
  /// files don't exclude, and the files at [paths], so that [referencesTo]
  /// finds the uses in them.
  Future<void> resolveAll(Iterable<String> paths) async {
    for (final path in {
      for (final context in _collection.contexts)
        ...context.contextRoot.analyzedFiles().where(
          (path) => path.endsWith('.dart'),
        ),
      ...paths,
    }) {
      await of(path);
    }
  }

  /// Returns the references of the declaration whose name starts at [name]
  /// in the file at [path], from the files resolved so far, or `null` when
  /// that file isn't resolved or no declaration's name starts there.
  List<Location>? referencesTo(String path, Position name) =>
      _elements[path]?[name]?.let(_index.referencesTo);

  /// Returns the locations of the names of the members that override the
  /// member whose name starts at [name] in the file at [path], among the
  /// files resolved so far, or none when that file isn't resolved or no
  /// member's name starts there.
  List<Location> overridesOf(String path, Position name) =>
      _elements[path]?[name]?.let(_hierarchy.overridesOf) ?? const [];

  /// Returns whether the signature of the function, method or constructor
  /// whose name starts at [name] in the file at [path] has a type through
  /// which a caller can invoke any member: `dynamic`, as in
  /// `void f(dynamic cb)` and in `f()`, whose return type is omitted, or a
  /// bare `Function`. Returns `null` when that file isn't resolved or no
  /// function, method or constructor's name starts there.
  bool? hasDynamicSignature(String path, Position name) =>
      switch (_elements[path]?[name]) {
        final ExecutableElement function => _hasDynamicType(function.type),
        _ => null,
      };

  /// Ends the analysis.
  Future<void> dispose() => _collection.dispose();

  Future<ResolvedFile?> _resolve(String path) async {
    for (final context in _contextsFor(path)) {
      // A file that can't be read resolves as empty, but isn't.
      if (await context.currentSession.getResolvedUnit(path)
          case ResolvedUnitResult(exists: true) && final result) {
        _hierarchy.add(result.unit);
        _index.add(path, result.unit);
        final (:outline, :elements, :annotations) = unitOutline(result.unit);
        _elements[path] = elements;
        return _resolved[path] = _fileOf(
          result,
          outline,
          annotations,
          _packages.configOf(p.dirname(path)),
        );
      }
    }
    return null;
  }

  ParsedUnitResult? _parse(String path) => _contextsFor(path)
      .map((context) => context.currentSession.getParsedUnit(path))
      .whereType<ParsedUnitResult>()
      .firstOrNull;

  /// The contexts that may resolve [path], first those whose root holds it,
  /// the deepest first. A file of a dependency is in no context's root, and
  /// a file that `analysis_options.yaml` excludes is in one that doesn't
  /// analyze it, but every context that has the file's package can resolve
  /// it.
  List<AnalysisContext> _contextsFor(String path) {
    final contexts = _collection.contexts;
    final holding = contexts
        .where((context) => p.isWithin(_rootOf(context), path))
        .sorted((a, b) => _rootOf(b).length.compareTo(_rootOf(a).length));
    return [...holding, ...contexts.whereNot(holding.contains)];
  }

  static String _rootOf(AnalysisContext context) =>
      context.contextRoot.root.path;

  /// Returns [result], whose outline is [outline], as ciach reads it.
  /// [annotations] are the annotations of each declaration, by the start of
  /// its name, and [config] is the package config of the file, which gives
  /// the package of a file outside `lib/`.
  static ResolvedFile _fileOf(
    ResolvedUnitResult result,
    Outline outline,
    Map<Position, List<Annotation>> annotations,
    PackageConfig? config,
  ) {
    final positionOf = result.lineInfo.positionOf;
    ResolvedClass classOf(InterfaceElement type) =>
        .new(type.displayName, _packageOf(type.library, config));

    Set<ResolvedClass> supertypesOf(InterfaceElement type) => {
      for (final supertype in type.allSupertypes) classOf(supertype.element),
    };

    return .new(
      content: result.content,
      markers: .parse(result.content, lineCommentsOf(result.unit)),
      outline: outline,
      annotations: {
        for (final MapEntry(key: name, value: declared) in annotations.entries)
          name: [
            for (final annotation in declared)
              DeclarationAnnotation(
                _nameOf(annotation).name,
                package: annotation.element?.library?.let(
                  (library) => _packageOf(library, config),
                ),
                argument: switch (annotation.arguments?.arguments.firstOrNull) {
                  StringLiteral(:final stringValue?) => stringValue,
                  _ => null,
                },
                createdClass: switch (annotation.element) {
                  ConstructorElement(enclosingElement: final type) => .new(
                    classOf(type),
                    supertypesOf(type),
                  ),
                  _ => null,
                },
              ),
          ],
      },
      supertypes: {
        for (final declaration in result.unit.declarations)
          if (declaration.declaredFragment case Fragment(
            element: final InterfaceElement type &&
                (ClassElement() || MixinElement()),
            :final nameOffset?,
          ))
            positionOf(nameOffset): supertypesOf(type),
      },
      needSuperArguments: {
        for (final declaration in result.unit.declarations)
          if (declaration.declaredFragment
              case Fragment(
                element: ClassElement(
                  supertype: InterfaceType(
                    element: ClassElement(:final unnamedConstructor),
                  ),
                ),
                :final nameOffset?,
              )
              when unnamedConstructor?.formalParameters.any(
                    (parameter) => parameter.isRequired,
                  ) ??
                  true)
            positionOf(nameOffset),
      },
      firstError:
          minBy(
            result.diagnostics.where(
              (diagnostic) => diagnostic.severity == .error,
            ),
            (diagnostic) => diagnostic.offset,
          )?.let(
            (error) =>
                (position: positionOf(error.offset), message: error.message),
          ),
    );
  }

  /// Whether [type] is `dynamic` or a bare `Function`, or has such a type in
  /// its type arguments, parameters, return type or fields, as
  /// `List<dynamic>` and `void Function(Function)` do.
  static bool _hasDynamicType(DartType type) => switch (type) {
    DynamicType() || InterfaceType(isDartCoreFunction: true) => true,
    InterfaceType(:final typeArguments) => typeArguments.any(_hasDynamicType),
    FunctionType(:final returnType, :final formalParameters) =>
      _hasDynamicType(returnType) ||
          formalParameters.any((parameter) => _hasDynamicType(parameter.type)),
    RecordType(:final positionalFields, :final namedFields) => [
      ...positionalFields,
      ...namedFields,
    ].any((field) => _hasDynamicType(field.type)),
    _ => false,
  };

  /// The name that follows the `@` of [annotation] and its import prefix:
  /// `Preview` in `@prefix.Preview.named()` and in `@Preview.named()`.
  static Identifier _nameOf(Annotation annotation) => switch (annotation.name) {
    PrefixedIdentifier(
      prefix: SimpleIdentifier(element: PrefixElement()),
      :final identifier,
    ) =>
      identifier,
    PrefixedIdentifier(:final prefix) => prefix,
    final name => name,
  };

  /// The package that declares [library]: `flutter` for
  /// `package:flutter/widgets.dart`, the library itself for an SDK library,
  /// such as `dart:core`, and for a file outside `lib/`, the package of
  /// [config] whose root holds it.
  static String? _packageOf(LibraryElement library, PackageConfig? config) =>
      switch (library.uri) {
        Uri(scheme: 'package', pathSegments: [final package, _, ...]) =>
          package,
        Uri(scheme: 'dart') && final uri => '$uri',
        final uri => config?.packageOf(uri)?.name,
      };
}
