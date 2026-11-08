/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'package:analyzer/dart/analysis/analysis_context.dart';
import 'package:analyzer/dart/analysis/analysis_context_collection.dart';
import 'package:analyzer/dart/analysis/results.dart';
import 'package:analyzer/dart/ast/ast.dart';
import 'package:analyzer/dart/ast/visitor.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:ciach/src/analysis/line_positions.dart';
import 'package:ciach/src/analysis/resolved_class.dart';
import 'package:ciach/src/analysis/resolved_file.dart';
import 'package:ciach/src/analysis/unit_outline.dart';
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
final class ResolvedFiles {
  /// Creates the analysis of the Dart files under [root], an absolute and
  /// normalized path, with the Dart SDK at [sdkPath]. A file is resolved when
  /// it is first asked for.
  ResolvedFiles(String root, {required String sdkPath})
    : _collection = .new(includedPaths: [root], sdkPath: sdkPath);

  final AnalysisContextCollection _collection;
  final _packages = PackageResolver();
  late final _files = CachedMap<String, Future<ResolvedFile?>>(_resolve);

  /// Returns the file at [path], an absolute and normalized path, or `null`
  /// when the analyzer can't resolve it, such as a file whose path isn't the
  /// path of its URI.
  Future<ResolvedFile?> of(String path) => _files[path];

  /// Ends the analysis.
  Future<void> dispose() => _collection.dispose();

  Future<ResolvedFile?> _resolve(String path) async {
    for (final context in _contextsFor(path)) {
      if (await context.currentSession.getResolvedUnit(path)
          case final ResolvedUnitResult result) {
        return _fileOf(result, _packages.configOf(p.dirname(path)));
      }
    }
    return null;
  }

  /// The contexts that may resolve [path], first those whose root holds it,
  /// the deepest first. A file of a dependency is in no context's root, and
  /// a file that `analysis_options.yaml` excludes is in one that doesn't
  /// analyze it, but every context that has the file's package can resolve
  /// it.
  List<AnalysisContext> _contextsFor(String path) {
    final contexts = _collection.contexts;
    final holding =
        contexts.where((context) => p.isWithin(_rootOf(context), path)).toList()
          ..sort((a, b) => _rootOf(b).length.compareTo(_rootOf(a).length));
    return [...holding, ...contexts.whereNot(holding.contains)];
  }

  static String _rootOf(AnalysisContext context) =>
      context.contextRoot.root.path;

  /// Returns [result] as ciach reads it. [config] is the package config of
  /// the file, which gives the package of a file outside `lib/`.
  static ResolvedFile _fileOf(
    ResolvedUnitResult result,
    PackageConfig? config,
  ) {
    final positionOf = result.lineInfo.positionOf;
    ResolvedClass classOf(InterfaceElement type) =>
        .new(type.displayName, _packageOf(type.library, config));

    Set<ResolvedClass> supertypesOf(InterfaceElement type) => {
      for (final supertype in type.allSupertypes) classOf(supertype.element),
    };

    final annotations =
        (_Annotations()..visitCompilationUnit(result.unit)).annotations;
    return .new(
      outline: unitOutline(result.unit, result.lineInfo),
      annotationPackages: {
        for (final annotation in annotations)
          positionOf(_nameOf(annotation).offset): ?annotation.element?.library
              ?.let((library) => _packageOf(library, config)),
      },
      annotationClasses: {
        for (final annotation in annotations)
          if (annotation.element case ConstructorElement(
            enclosingElement: final type,
          ))
            positionOf(_nameOf(annotation).offset): .new(
              classOf(type),
              supertypesOf(type),
            ),
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

/// Collects the annotations of a file.
final class _Annotations extends RecursiveAstVisitor<void> {
  final annotations = <Annotation>[];

  @override
  void visitAnnotation(Annotation node) => annotations.add(node);
}
