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
import 'package:ciach/src/source/source_index.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show Position;

/// Which private types other libraries can reach through a public type, so
/// their instance members are as public as that type's.
///
/// A public type reaches a private one by naming it as a supertype, as in
/// `class Circle extends _Base {}`, where `Circle().area()` calls
/// `_Base.area`, or `abstract class Shape implements _Shape {}` and
/// `mixin Mixer on _Host {}`, directly or through other private types. The
/// analysis server's type hierarchy lists these subtypes, in any file of the
/// library. A public `typedef Alias = _Aliased;` reaches `_Aliased` too, when
/// it is in the same file.
///
/// A concrete class that implements a private type declares the members
/// itself, so the type's own are out of reach, but they count as reachable
/// too: a member wrongly called public is only skipped by `--no-public`.
final class ExposedTypes {
  ExposedTypes(this._sources);

  final SourceIndex _sources;

  static const _unreadSubtypes =
      'Could not list the subtypes; its members count as public.';

  /// Whether a type has a public subtype, by the position of its name.
  final _bySubtypes = <(Uri, Position), Future<bool>>{};

  /// The private types declared in [path], whose outline is [unit], that a
  /// public type reaches.
  Future<Set<String>> of(LspClient client, String path, Outline unit) async {
    final types = [
      for (final type in unit.children)
        if (_isPrivateType(type.element)) type.element,
    ];
    if (types.isEmpty) {
      return const {};
    }
    final aliased = _aliasedPrivateNames(path, unit);
    final uri = File(path).uri;
    final exposed = await Future.wait([
      for (final type in types)
        if (aliased.contains(type.name))
          Future.value(true)
        else
          _hasPublicSubtype(client, uri, type.range!.start, path),
    ]);
    return {
      for (final (i, type) in types.indexed)
        if (exposed[i]) type.name,
    };
  }

  bool _isPrivateType(OutlineElement element) =>
      const <OutlineKind>{
        .class$,
        .mixin,
        .extensionType,
      }.contains(element.kind) &&
      element.range != null &&
      isPrivateName(element.name);

  /// The private names in the public type aliases of [unit].
  Set<String> _aliasedPrivateNames(String path, Outline unit) => {
    for (final alias in unit.children)
      if (alias.element.kind == .typeAlias &&
          !isPrivateName(alias.element.name))
        for (final token
            in _sources
                    .semanticTokens(path)
                    ?.between(alias.codeRange.start, alias.codeRange.end) ??
                const <SemanticToken>[])
          if (!token.isKeyword && !token.isComment && isPrivateName(token.text))
            token.text,
  };

  Future<bool> _hasPublicSubtype(
    LspClient client,
    Uri uri,
    Position name,
    String path,
  ) => _bySubtypes.putIfAbsent((
    uri,
    name,
  ), () => _queryPublicSubtype(client, uri, name, path));

  Future<bool> _queryPublicSubtype(
    LspClient client,
    Uri uri,
    Position name,
    String path,
  ) async {
    try {
      for (final subtype in await client.subtypesOf(uri, name)) {
        if (!isPrivateName(subtype.name) ||
            await _hasPublicSubtype(
              client,
              Uri.parse(subtype.uri),
              subtype.selectionRange.start,
              SourceIndex.pathOf(subtype.uri),
            )) {
          return true;
        }
      }
      return false;
    } on LspRequestException catch (e) {
      recordProblem(_unreadSubtypes, e, path: path, position: name);
      return true;
    }
  }
}
