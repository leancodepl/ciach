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
import 'package:ciach/src/workspace/packages.dart';
import 'package:pro_lsp/pro_lsp.dart' show TypeHierarchyItem;

/// The members of a private type that other libraries can reach through a
/// public declaration.
enum ExposedMembers {
  /// The instance members, which a public subtype inherits.
  instance,

  /// All of them, which a public type alias names: `Alias.create()` calls a
  /// constructor and `Alias.util()` a static method.
  all,
}

/// Which private types other libraries can reach through a public
/// declaration, so their members are as public as that declaration.
///
/// A public type reaches a private one by naming it as a supertype, as in
/// `class Circle extends _Base {}`, where `Circle().area()` calls
/// `_Base.area`, or `abstract class Shape implements _Shape {}` and
/// `mixin Mixer on _Host {}`, directly or through other private types. The
/// analysis server's type hierarchy lists these subtypes, in any file of the
/// library. A public `typedef Alias = _Aliased;` in any file of the library
/// reaches `_Aliased` too.
///
/// A concrete class that implements a private type declares the members
/// itself, so the type's own are out of reach, but they count as reachable
/// too: a member wrongly called public is only skipped by `--no-public`.
/// For the same reason, a type whose library can't be read counts as
/// reachable.
final class ExposedTypes {
  ExposedTypes(this._client, this._sources);

  final LspClient _client;
  final SourceIndex _sources;
  final _packages = PackageResolver();

  static const _unreadSubtypes =
      'Could not list the subtypes; its members count as public.';

  static const _unreadAliases =
      'Could not read the type aliases of the library; the members of its private types count as public.';

  late final _outlines = CachedMap<String, Future<Outline>>(
    (path) => _client.outline(File(path).uri),
  );

  late final _hasPublicSubtype = CachedMap<TypeHierarchyItem, Future<bool>>(
    _queryPublicSubtype,
  );

  /// The private names that the public type aliases of a library name, by
  /// the path of the library; `null` when a file of it can't be read.
  late final _aliasedIn = CachedMap<String, Future<Set<String>?>>(_readAliases);

  /// The private types declared in [path], whose outline is [unit], whose
  /// members a public declaration exposes, and which of them it exposes.
  Future<Map<String, ExposedMembers>> of(String path, Outline unit) async {
    final types = unit.children
        .map((type) => type.element)
        .where(_isExposablePrivateType);
    if (types.isEmpty) {
      return const {};
    }
    _outlines[path] = .value(unit);
    final aliased = await libraryOf(path, _packages)?.let(_aliasedIn.get);
    final exposed = await Future.wait([
      for (final type in types)
        _exposedMembers(path, type, aliased).then((members) => (type, members)),
    ]);
    return {for (final (type, members) in exposed) type.name: ?members};
  }

  Future<ExposedMembers?> _exposedMembers(
    String path,
    OutlineElement type,
    Set<String>? aliased,
  ) async {
    if (aliased == null || aliased.contains(type.name)) {
      return .all;
    }
    try {
      final item = await _client.typeHierarchyItemAt(
        File(path).uri,
        type.range!.start,
      );
      if (item == null || !await _hasPublicSubtype[item]) {
        return null;
      }
      return .instance;
    } on LspRequestException catch (e) {
      recordProblem(
        _unreadSubtypes,
        e,
        path: path,
        position: type.range!.start,
      );
      return .instance;
    }
  }

  /// Whether [element] is a private class, mixin or extension type, whose
  /// members a public declaration may expose.
  static bool _isExposablePrivateType(OutlineElement element) =>
      const <OutlineKind>{
        .class$,
        .mixin,
        .extensionType,
      }.contains(element.kind) &&
      element.range != null &&
      isPrivateName(element.name);

  Future<bool> _queryPublicSubtype(TypeHierarchyItem type) async {
    try {
      final subtypes = await _client.subtypesOf(type);
      if (!subtypes.every((subtype) => isPrivateName(subtype.name))) {
        return true;
      }
      final viaPrivate = await Future.wait(subtypes.map(_hasPublicSubtype.get));
      return viaPrivate.contains(true);
    } on LspRequestException catch (e) {
      recordProblem(
        _unreadSubtypes,
        e,
        path: SourceIndex.pathOf(type.uri),
        position: type.selectionRange.start,
      );
      return true;
    }
  }

  Future<Set<String>?> _readAliases(String library) async {
    try {
      final perFile = await Future.wait(
        filesOfLibrary(library, _packages).map(_aliasedNamesIn),
      );
      return {for (final names in perFile) ...names};
    } on LspRequestException catch (e) {
      recordProblem(_unreadAliases, e, path: library);
      return null;
    }
  }

  /// The private names in the public type aliases of [path].
  Future<Set<String>> _aliasedNamesIn(String path) async {
    final aliases = (await _outlines[path]).children.where(
      (alias) =>
          alias.element.kind == .typeAlias &&
          !isPrivateName(alias.element.name),
    );
    if (aliases.isEmpty) {
      return const {};
    }
    final tokens =
        _sources.semanticTokens(path) ??
        await _client.semanticTokens(File(path).uri, _sources.lines(path));
    return {
      for (final alias in aliases)
        for (final token in tokens.between(
          alias.codeRange.start,
          alias.codeRange.end,
        ))
          if (!token.isKeyword && !token.isComment && isPrivateName(token.text))
            token.text,
    };
  }
}
