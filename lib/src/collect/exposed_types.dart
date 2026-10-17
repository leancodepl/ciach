/*
 * AI-Provenance:
 *   model: claude-opus-5-5
 *   harness: Claude Code
 */

import 'dart:io';

import 'package:ciach/src/lsp/exceptions.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/lsp/problems.dart';
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/source/directives.dart';
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/cached_map.dart';
import 'package:ciach/src/util/extensions.dart';
import 'package:ciach/src/util/reachability.dart';
import 'package:ciach/src/workspace/packages.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// The members of a private type that other libraries can reach through a
/// public declaration.
enum ExposedMembers {
  /// The instance members, which a value of the type or of a public subtype
  /// lets other libraries call.
  instance,

  /// All of them, which a public type alias names: `Alias.create()` calls a
  /// constructor and `Alias.util()` a static method.
  all,
}

/// Which private types other libraries can reach through a public
/// declaration, so that their members count as public.
///
/// A public declaration in any file of the library exposes the private types
/// that its signature or header names, such as `_Tool` in `_Tool makeTool()`.
/// An exposed private type exposes the ones that its own signatures name. A
/// body never hands a type out.
final class ExposedTypes {
  ExposedTypes(this._client, this._sources);

  final LspClient _client;
  final SourceIndex _sources;
  final _packages = PackageResolver();

  static const _unreadLibrary =
      'Could not read the library; the members of its private types count as public.';

  late final _outlines = CachedMap<String, Future<Outline>>(
    (path) => _client.outline(File(path).uri),
  );

  /// The private names that each library exposes, by the path of the
  /// library; `null` when a file of it can't be read.
  late final _exposedIn =
      CachedMap<String, Future<Map<String, ExposedMembers>?>>(_readLibrary);

  /// The private types declared in [path], whose outline is [unit], whose
  /// members a public declaration exposes, and which of them it exposes; all
  /// of them when the library can't be read.
  Future<Map<String, ExposedMembers>> of(String path, Outline unit) async {
    final types = unit.children
        .map((type) => type.element)
        .where(_isExposablePrivateType);
    if (types.isEmpty) {
      return const {};
    }
    _outlines[path] = .value(unit);
    final exposed = await libraryOf(path, _packages)?.let(_exposedIn.get);
    return switch (exposed) {
      null => {for (final type in types) type.name: .all},
      _ => {for (final type in types) type.name: ?exposed[type.name]},
    };
  }

  /// Whether [element] is a private class, mixin, enum or extension type,
  /// whose members a public declaration may expose.
  static bool _isExposablePrivateType(OutlineElement element) =>
      const <OutlineKind>{
        .class$,
        .mixin,
        .enum$,
        .extensionType,
      }.contains(element.kind) &&
      element.range != null &&
      isPrivateName(element.name);

  Future<Map<String, ExposedMembers>?> _readLibrary(String library) async {
    try {
      final perFile = await Future.wait(
        filesOfLibrary(library, _packages).map(_mentionsIn),
      );
      return _exposedBy(perFile.flattened);
    } on LspRequestException catch (e) {
      recordProblem(_unreadLibrary, e, path: library);
      return null;
    }
  }

  /// Returns the private names that the public declarations among
  /// [mentions] reach, directly or through other private names, and which
  /// members of each they expose.
  static Map<String, ExposedMembers> _exposedBy(Iterable<_Mention> mentions) {
    final byCarrier = mentions.groupSetsBy((mention) => mention.carrier);
    final reached = reachableFrom<String?>([
      null,
    ], (carrier) => byCarrier[carrier]?.map((mention) => mention.name) ?? []);
    final all = {
      for (final mention in mentions)
        if (mention.members == .all && reached.contains(mention.carrier))
          mention.name,
    };
    return {
      for (final name in reached.nonNulls)
        name: all.contains(name) ? .all : .instance,
    };
  }

  Future<Iterable<_Mention>> _mentionsIn(String path) async {
    final unit = await _outlines[path];
    final tokens =
        _sources.semanticTokens(path) ??
        await _client.semanticTokens(File(path).uri, _sources.lines(path));
    final perDeclaration = await Future.wait(
      unit.children.map((node) => _mentionsBy(path, node, tokens)),
    );
    return perDeclaration.flattened;
  }

  /// Returns the private names that the top-level declaration [node] names
  /// where other libraries can reach them.
  Future<Iterable<_Mention>> _mentionsBy(
    String path,
    Outline node,
    List<SemanticToken> tokens,
  ) async => switch (node.element) {
    OutlineElement(isUnnamedExtension: true) => const [],
    OutlineElement(
      kind: .class$ || .mixin || .enum$ || .extension || .extensionType,
    ) =>
      await _typeMentions(path, node, tokens),
    OutlineElement(kind: .typeAlias || .functionTypeAlias || .classTypeAlias) =>
      _aliasMentions(path, node, tokens),
    OutlineElement(
      kind: .function || .getter || .setter || .topLevelVariable,
      :final name,
    )
        when !isPrivateName(name) =>
      [
        for (final type in await _signatureNames(path, node))
          _Mention(null, type),
      ],
    _ => const [],
  };

  Future<Iterable<_Mention>> _typeMentions(
    String path,
    Outline node,
    List<SemanticToken> tokens,
  ) async {
    final carrier = _carrierOf(node.element);
    final members = await Future.wait(
      node.children
          .where((member) => _isPublicMember(member, node.element.name))
          .map((member) => _signatureNames(path, member)),
    );
    return [
      for (final name in {
        ..._headerNames(path, node, tokens),
        ...members.flattened,
      })
        _Mention(carrier, name),
    ];
  }

  /// Returns the private names in the type alias [node]. The type that a
  /// public `typedef Alias = _Aliased;` names first exposes all of its
  /// members, since `Alias.create()` calls a constructor.
  Iterable<_Mention> _aliasMentions(
    String path,
    Outline node,
    List<SemanticToken> tokens,
  ) {
    final element = node.element;
    final carrier = _carrierOf(element);
    // A function type alias can name a type before its own name:
    // `typedef _Item Make();`.
    final names = _privateNames(
      tokens.between(node.codeRange.start, node.codeRange.end),
    );
    if (element.kind != .typeAlias) {
      return names.map((name) => _Mention(carrier, name));
    }
    final aliased = _typeParametersEnd(path, element)?.let(
      (end) => tokens
          .between(end, node.codeRange.end)
          .firstWhereOrNull((token) => !token.isComment),
    );
    return names.map(
      (name) => _Mention(
        carrier,
        name,
        aliased == null || name == aliased.text ? .all : .instance,
      ),
    );
  }

  /// Returns the private names in the header of the type [node] that expose
  /// a type, such as `_Base` in `class Circle extends _Base`. A bound counts
  /// only when the type uses its type parameters, and the `on` type of an
  /// extension never does. A type that a concrete class implements counts
  /// too: removing one of its members also removes the override.
  Iterable<String> _headerNames(
    String path,
    Outline node,
    List<SemanticToken> tokens,
  ) {
    final element = node.element;
    final nameEnd = element.range!.end;
    final bodyStart =
        node.children.firstOrNull?.range.start ?? node.codeRange.end;
    final listEnd = _typeParametersEnd(path, element);
    if (listEnd == null) {
      return _privateNames(tokens.between(nameEnd, bodyStart));
    }
    final usesTypeParameters = tokens
        .between(listEnd, node.codeRange.end)
        .any((token) => token.type == 'typeParameter');
    return _privateNames([
      if (usesTypeParameters) ...tokens.between(nameEnd, listEnd),
      if (element.kind != .extension) ...tokens.between(listEnd, bodyStart),
    ]);
  }

  /// Returns where the type parameters of [element] end in [path], or where
  /// its name ends when it has none; `null` when the source doesn't match the
  /// text that the outline gives for them.
  Position? _typeParametersEnd(String path, OutlineElement element) {
    final nameEnd = element.range!.end;
    final typeParameters = element.typeParameters;
    if (typeParameters == null || typeParameters.isEmpty) {
      return nameEnd;
    }
    final start = _sources.offsetOf(path, nameEnd);
    // The outline gives the type parameters as text without line breaks:
    // `<T extends _S, U>`. Matching its characters with any whitespace in
    // between finds where the list ends in the source.
    final list = RegExp(
      [
        '',
        ...typeParameters.replaceAll(RegExp(r'\s'), '').split(''),
      ].map(RegExp.escape).join(r'\s*'),
    );
    return start
        ?.let((start) => list.matchAsPrefix(_sources.content(path), start))
        ?.end
        .let((end) => _sources.positionOf(path, end));
  }

  /// Returns the private names in the signature of [node]: its type
  /// parameters, parameters and declared type, or the type that the server
  /// infers for a variable without one.
  Future<Set<String>> _signatureNames(String path, Outline node) async {
    final OutlineElement(
      :kind,
      :range,
      :returnType,
      :parameters,
      :typeParameters,
    ) = node.element;
    final signature = switch ((kind, returnType)) {
      (.field || .topLevelVariable, '') =>
        await _client.hover(File(path).uri, range!.start) ?? '',
      _ => [?typeParameters, ?parameters, ?returnType].join(' '),
    };
    return {for (final match in _privateName.allMatches(signature)) match[0]!};
  }

  static String? _carrierOf(OutlineElement type) =>
      isPrivateName(type.name) ? type.name : null;

  /// Whether other libraries can name [member] of the type [type].
  static bool _isPublicMember(Outline member, String type) =>
      !isPrivateName(switch (member.element) {
        OutlineElement(kind: .constructor, :final name) => constructorName(
          name,
          type,
        ),
        OutlineElement(:final name) => name,
      });

  static Set<String> _privateNames(Iterable<SemanticToken> tokens) => {
    for (final token in tokens)
      if (!token.isComment && isPrivateName(token.text)) token.text,
  };
}

/// A private name that a declaration names where other libraries can reach
/// it: [carrier] is the private declaration that names it, or `null` for a
/// public declaration.
final class _Mention {
  const _Mention(this.carrier, this.name, [this.members = .instance]);

  final String? carrier;
  final String name;

  /// The members of [name] that [carrier] exposes when other libraries can
  /// reach it.
  final ExposedMembers members;
}

/// A private name in a signature, which the outline and a hover give only as
/// text.
final _privateName = RegExp(r'(?<![\w$])_[\w$]*');
