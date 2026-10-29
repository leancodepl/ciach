/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

/// Resolves the classes that the entry-point rules read: the class of each
/// annotation that creates an object, such as `@DarkPreview()` or `@preview`,
/// and the supertypes of each class. A rule can then match a subtype of the
/// class that it names.
library;

import 'dart:io';
import 'dart:math';

import 'package:ciach/src/conventions/entry_points.dart';
import 'package:ciach/src/conventions/resolved_declaration.dart';
import 'package:ciach/src/fetch/reference_fetch.dart';
import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:package_config/package_config.dart';
import 'package:path/path.dart' as p;
import 'package:pro_lsp/pro_lsp.dart'
    show DocumentSymbol, Location, Position, TypeHierarchyItem;

const _unresolvedAnnotation =
    'Could not resolve the class of this annotation; the declaration that it annotates may be reported.';

const _unresolvedClass =
    'Could not resolve the supertypes of this class; its members may be reported.';

/// A class with all its supertypes.
typedef _Hierarchy = ({ResolvedClass type, Set<ResolvedClass> supertypes});

/// The classes of the annotations and the supertypes of the classes in the
/// scanned files, resolved only as far as the entry-point rules read them.
final class ResolvedClasses {
  ResolvedClasses(this._sources, List<EntryPoint> rules)
    : _resolvesAnnotations = rules.any((rule) => rule is AnnotatedEntryPoint),
      _resolvesConstants = rules.any(
        (rule) => rule is AnnotatedEntryPoint && rule.constants,
      ),
      _resolvesSupertypes = rules.any((rule) => rule is SubtypeEntryPoint);

  final SourceIndex _sources;
  final bool _resolvesAnnotations;
  final bool _resolvesConstants;
  final bool _resolvesSupertypes;
  final _packages = PackageResolver();

  /// The annotations, by the file and the position of the name that the
  /// annotation's `@` is followed by: `Preview` in `@Preview()`, `preview`
  /// in `@preview`.
  final _byAnnotation = <(String, Position), List<ResolvedAnnotation>>{};

  /// The supertypes of each class, by the file and the position of the
  /// class's name.
  final _byClassName = <(String, Position), Set<ResolvedClass>>{};

  /// The classes that a definition declares, by its file and position. The
  /// same annotation in many places has the same definition.
  final _byDefinition = <(String, Position), Future<List<_Hierarchy>>>{};

  /// The classes of the objects that a constant holds, by the position of
  /// its definition.
  final _byConstant = <(String, Position), Future<List<_Hierarchy>>>{};

  /// A class and all its supertypes, by the file and the position of the
  /// class's name in its declaration.
  final _byClass = <(String, Position), Future<Set<ResolvedClass>>>{};

  /// Resolves the annotations among [tokens] and the classes among [symbols],
  /// the semantic tokens and the document symbols of the open file [path],
  /// so that [annotationsOf] and [supertypesOf] can return them.
  Future<void> resolve(
    LspClient client,
    String path,
    List<SemanticToken> tokens,
    List<DocumentSymbol> symbols,
  ) async {
    final config = _packages.configOf(p.dirname(path));
    await Future.wait([
      if (_resolvesAnnotations)
        for (final token in _constructorNames(tokens))
          _resolveAnnotation(client, config, path, token, readsConstant: false),
      if (_resolvesConstants)
        for (final token in tokens.where(_isConstantName))
          _resolveAnnotation(client, config, path, token, readsConstant: true),
      if (_resolvesSupertypes)
        for (final symbol in symbols.where((s) => s.kind == .class$))
          _resolveClass(client, config, path, symbol),
    ]);
  }

  /// Returns the annotations among [leadingMetadata], the doc comment and
  /// annotation tokens of a declaration in [path].
  List<ResolvedAnnotation> annotationsOf(
    String path,
    Iterable<SemanticToken> leadingMetadata,
  ) => [
    for (final token in leadingMetadata) ...?_byAnnotation[(path, token.start)],
  ];

  /// Returns all the supertypes of the class [symbol] in [path].
  Set<ResolvedClass> supertypesOf(String path, DocumentSymbol symbol) =>
      _byClassName[(path, symbol.selectionRange.start)] ?? const {};

  /// Returns the class or typedef name of each annotation among [tokens]
  /// that calls a constructor: `Preview` in `@Preview()`, and `AliasPreview`
  /// in `@prefix.AliasPreview()`.
  static Iterable<SemanticToken> _constructorNames(
    List<SemanticToken> tokens,
  ) sync* {
    for (final (i, token) in tokens.indexed) {
      if (!_readsConstant(tokens, i) &&
          (token.isAnnotationClassName ||
              (token.type == 'type' && _followsAt(tokens, i)))) {
        yield token;
      }
    }
  }

  /// Whether [token] is the name of a constant that an annotation reads, such
  /// as `preview` in `@preview` and `held` in `@Holder.held`.
  static bool _isConstantName(SemanticToken token) =>
      token.type == 'property' && token.modifiers.contains('annotation');

  /// Whether the class or typedef name at [index] of [tokens] is followed by
  /// a `.` and a constant, as `Holder` in `Holder.held` is, so that it calls
  /// no constructor.
  static bool _readsConstant(List<SemanticToken> tokens, int index) =>
      switch (tokens.skip(index + 1).take(2).toList()) {
        [SemanticToken(text: '.'), SemanticToken(type: 'property')] => true,
        _ => false,
      };

  /// Whether the token at [index] of [tokens] comes right after an `@`, or
  /// after an `@` and an import prefix.
  ///
  /// The server marks a typedef name with no `annotation` modifier, so only
  /// its place tells that it names the annotation and not one of its type
  /// arguments.
  static bool _followsAt(List<SemanticToken> tokens, int index) =>
      switch (tokens.sublist(max(0, index - 3), index).reversed.toList()) {
        [SemanticToken(text: '@'), ...] => true,
        [
          SemanticToken(text: '.'),
          SemanticToken(:final modifiers),
          SemanticToken(text: '@'),
        ]
            when modifiers.contains('importPrefix') =>
          true,
        _ => false,
      };

  /// Records the annotation that [token] names. Records nothing when its
  /// class can't be resolved.
  Future<void> _resolveAnnotation(
    LspClient client,
    PackageConfig? config,
    String path,
    SemanticToken token, {
    required bool readsConstant,
  }) async {
    try {
      final definitions = await client.definition(File(path).uri, token.start);
      final classes = await Future.wait([
        for (final definition in definitions)
          if (readsConstant)
            _heldBy(client, config, definition)
          else
            _declaredAt(client, config, definition),
      ]);
      _byAnnotation[(path, token.start)] = [
        for (final (:type, :supertypes) in classes.flattened)
          .new(type, supertypes, readsConstant: readsConstant),
      ];
    } on LspRequestException catch (e) {
      recordProblem(
        _unresolvedAnnotation,
        e,
        path: path,
        position: token.start,
      );
    }
  }

  /// Records the supertypes of the class [symbol].
  Future<void> _resolveClass(
    LspClient client,
    PackageConfig? config,
    String path,
    DocumentSymbol symbol,
  ) async {
    final name = symbol.selectionRange.start;
    try {
      final items = await client.typeHierarchyItems(File(path).uri, name);
      final hierarchies = await Future.wait([
        for (final item in items) _hierarchyOf(client, config, item),
      ]);
      _byClassName[(path, name)] = {
        for (final (:supertypes, type: _) in hierarchies) ...supertypes,
      };
    } on LspRequestException catch (e) {
      recordProblem(_unresolvedClass, e, path: path, position: name);
    }
  }

  /// Returns the classes declared at [definition] with their supertypes. For
  /// a typedef, which declares no class, they are those of the type that it
  /// names.
  Future<List<_Hierarchy>> _declaredAt(
    LspClient client,
    PackageConfig? config,
    Location definition,
  ) => _byDefinition[(definition.uri, definition.range.start)] ??= () async {
    final items = await client.typeHierarchyItems(
      .parse(definition.uri),
      definition.range.start,
    );
    if (items.isNotEmpty) {
      return await Future.wait([
        for (final item in items) _hierarchyOf(client, config, item),
      ]);
    }
    return switch (await _valueAfter(client, definition)) {
      SemanticToken(type: 'class' || 'type') && final value => await _classesAt(
        client,
        config,
        definition,
        value,
        _declaredAt,
      ),
      _ => const <_Hierarchy>[],
    };
  }();

  /// Returns the classes of the objects that the constant declared at
  /// [definition] holds, with their supertypes: `Preview` for
  /// `const preview = Preview();`. It follows a constant that holds another
  /// one. Returns nothing for a value that no constructor call creates, such
  /// as a list.
  Future<List<_Hierarchy>> _heldBy(
    LspClient client,
    PackageConfig? config,
    Location definition,
  ) => _byConstant[(definition.uri, definition.range.start)] ??= () async {
    return switch (await _valueAfter(client, definition)) {
      SemanticToken(type: 'class' || 'type') && final value => await _classesAt(
        client,
        config,
        definition,
        value,
        _declaredAt,
      ),
      SemanticToken(type: 'property' || 'variable') && final value =>
        await _classesAt(client, config, definition, value, _heldBy),
      _ => const <_Hierarchy>[],
    };
  }();

  /// Returns what [resolve] gives for each definition of [value], a token in
  /// the file of [definition].
  Future<List<_Hierarchy>> _classesAt(
    LspClient client,
    PackageConfig? config,
    Location definition,
    SemanticToken value,
    Future<List<_Hierarchy>> Function(
      LspClient client,
      PackageConfig? config,
      Location definition,
    )
    resolve,
  ) async {
    final definitions = await client.definition(
      .parse(definition.uri),
      value.start,
    );
    final classes = await Future.wait([
      for (final definition in definitions) resolve(client, config, definition),
    ]);
    return classes.flattened.toList();
  }

  /// Returns the token that names the value after the `=` of the typedef or
  /// constant named at [name]: `Plain` in `typedef AliasPlain = Plain;`,
  /// `Story` in `const story = Story();` and `held` in
  /// `const story = Holder.held;`. Returns `null` when nothing but `const`,
  /// `new` and an import prefix comes between the `=` and the name.
  Future<SemanticToken?> _valueAfter(LspClient client, Location name) async {
    final path = SourceIndex.pathOf(name.uri);
    if (!_sources.hasSemanticTokens(path)) {
      _sources.cacheSemanticTokens(
        path,
        await semanticTokensOrEmpty(client, _sources, path),
      );
    }
    final tokens = _sources.semanticTokens(path)!;
    final content = _sources.content(path);
    // The server gives `=` no token, so it is found in the text. It comes
    // after the type parameters of a typedef, whose bounds can't hold one.
    final equals = _sources
        .offsetOf(path, name.range.start)
        ?.let((offset) => content.indexOfOrNull('=', offset));
    if (equals == null) {
      return null;
    }
    final value = tokens
        .skip(tokens.firstIndexAtOrAfter(_sources.positionOf(path, equals)))
        .firstWhereOrNull(
          (token) =>
              !token.isKeyword &&
              !token.modifiers.contains('importPrefix') &&
              token.text != '.',
        );
    if (value == null) {
      return null;
    }
    final between = content.substring(
      equals + 1,
      _sources.offsetOf(path, value.start),
    );
    if (!_beforeValue.hasMatch(between)) {
      return null;
    }
    // In `Holder.held`, the value is the constant `held`.
    final next = tokens.elementAtOrNull(
      tokens.firstIndexAtOrAfter(value.start) + 1,
    );
    if (next case SemanticToken(type: 'property')
        when _dot.hasMatch(
          content.substring(
            _sources.offsetOf(path, value.start)! + value.length,
            _sources.offsetOf(path, next.start),
          ),
        )) {
      return next;
    }
    return value;
  }

  /// Matches what may come between the `=` and the name of the value:
  /// `const`, `new` and an import prefix. Regexes read the text around the
  /// value because the server gives none of `=`, `.`, `[` and `(` a token
  /// there.
  static final _beforeValue = RegExp(
    r'^\s*(?:(?:const|new)\s+)?(?:[A-Za-z_$][\w$]*\s*\.\s*)?$',
  );

  /// Matches the `.` between a class name and a static constant.
  static final _dot = RegExp(r'^\s*\.\s*$');

  /// Returns the class of [item] with all its supertypes. Their packages are
  /// those that [config] gives the files that declare them.
  Future<_Hierarchy> _hierarchyOf(
    LspClient client,
    PackageConfig? config,
    TypeHierarchyItem item,
  ) async {
    final type = _classOf(config, item);
    final all = await _withSupertypes(client, config, item);
    return (type: type, supertypes: {...all}..remove(type));
  }

  /// Returns the class of [item] and all its supertypes.
  Future<Set<ResolvedClass>> _withSupertypes(
    LspClient client,
    PackageConfig? config,
    TypeHierarchyItem item,
  ) => _byClass[(item.uri, item.selectionRange.start)] ??= () async {
    final supertypes = await client.supertypes(item);
    final classes = await Future.wait([
      for (final supertype in supertypes)
        _withSupertypes(client, config, supertype),
    ]);
    return {_classOf(config, item), for (final set in classes) ...set};
  }();

  /// Returns the class that [item] names. The server names a generic class
  /// `Story<T>`.
  static ResolvedClass _classOf(
    PackageConfig? config,
    TypeHierarchyItem item,
  ) => .new(
    item.name.withoutTypeArguments,
    config?.toPackageUri(.parse(item.uri))?.pathSegments.first,
  );
}
