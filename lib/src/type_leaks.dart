import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/public_api.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position, Range;

/// Unexported types another package may still hold an instance of.
///
/// A type leaks when it is named outside a function body in an importable
/// file: in a signature, a field initializer, a supertype or a typedef. A
/// mention inside another type counts only if that type leaks too. An
/// omitted return type is `dynamic`, so a body never leaks a type.
final class TypeLeaks {
  TypeLeaks._(this._sealed);

  static Future<TypeLeaks> find({
    required LspClient client,
    required SourceIndex sources,
    required PublicApi api,
    required List<Candidate> candidates,
    required List<List<Location>> refs,
  }) async {
    final types = <DeclKey, int>{
      for (var i = 0; i < candidates.length; i++)
        if (_isType(candidates[i])) candidates[i].key: i,
    };
    final outlines = <String, Outline?>{};
    Future<Outline?> outlineOf(String path) async {
      if (outlines.containsKey(path)) {
        return outlines[path];
      }
      Outline? outline;
      if (sources.scannedPaths.contains(path)) {
        try {
          outline = await client.outline(File(path).uri);
        } on LspRequestException {
          outline = null;
        }
      }
      return outlines[path] = outline;
    }

    final code = <String, String>{};
    final carriersOf = <DeclKey, Set<_Carrier>>{};
    for (final MapEntry(:key, value: i) in types.entries) {
      final type = candidates[i];
      final carriers = carriersOf[key] = {};
      for (final loc in refs[i]) {
        final path = SourceIndex.pathOf(loc.uri);
        final pos = loc.range.start;
        if (!api.isImportable(path) ||
            (path == type.path && _contains(type.outline.range, pos)) ||
            sources.isDocReference(loc)) {
          continue;
        }
        final unit = await outlineOf(path);
        if (unit == null) {
          carriers.add(const _Carrier.root());
          continue;
        }
        final content = code[path] ??= stripComments(sources.content(path));
        if (_carrierAt(unit, path, pos, sources, content) case final carrier?) {
          carriers.add(carrier);
        }
      }
    }

    final leaking = <DeclKey>{
      for (final key in types.keys)
        if (api.exposes(key.path, key.name) ||
            carriersOf[key]!.any((c) => c.isRoot))
          key,
    };
    bool leaks(_Carrier carrier) =>
        carrier.isRoot ||
        switch (carrier.extension) {
          true => api.exposes(carrier.key!.path, carrier.key!.name),
          false =>
            !types.containsKey(carrier.key) || leaking.contains(carrier.key),
        };
    for (var grew = true; grew;) {
      grew = false;
      for (final key in types.keys) {
        if (!leaking.contains(key) && carriersOf[key]!.any(leaks)) {
          grew = leaking.add(key) || grew;
        }
      }
    }
    return ._({
      for (final key in types.keys)
        if (!leaking.contains(key)) key,
    });
  }

  /// Types whose references were read and none of which leaks.
  final Set<DeclKey> _sealed;

  /// Whether another package may reach [member] of a type through an
  /// instance. Members of extensions are reached only by importing them.
  bool reaches(Candidate member) =>
      isGated(member) && !_sealed.contains(member.containerKey);

  /// Whether [member] is reachable only if its type leaks.
  static bool isGated(Candidate member) =>
      member.container != null &&
      member.containerOutline?.element.kind != .extension &&
      !isPrivateName(member.symbol.name);

  static bool _isType(Candidate candidate) =>
      candidate.container == null &&
      (typeLikeKinds.contains(candidate.symbol.kind) &&
          !candidate.isExtension &&
          !candidate.isEnumValue);

  static bool _contains(Range range, Position pos) =>
      range.start.atOrBefore(pos) && pos.atOrBefore(range.end);

  /// What the reference at [pos] hands out, or `null` when it sits in a body
  /// or a directive.
  static _Carrier? _carrierAt(
    Outline unit,
    String path,
    Position pos,
    SourceIndex sources,
    String content,
  ) {
    final top = unit.children.where((n) => _contains(n.range, pos)).firstOrNull;
    if (top == null) {
      return null;
    }
    final kind = top.element.kind;
    if (kind case .class$ || .mixin || .enum$ || .extension || .extensionType) {
      final member = top.children
          .where((n) => _contains(n.range, pos))
          .firstOrNull;
      if (member != null && _inBody(member, path, pos, sources, content)) {
        return null;
      }
      if (kind == .extension && top.element.isUnnamedExtension) {
        return null;
      }
      return .of(
        DeclKey(path, top.element.name),
        extension: kind == .extension,
      );
    }
    return _inBody(top, path, pos, sources, content) ? null : const .root();
  }

  /// Whether [pos] lies in the body of the function-like [node].
  static bool _inBody(
    Outline node,
    String path,
    Position pos,
    SourceIndex sources,
    String content,
  ) {
    if (node.element.kind
        case .field ||
            .topLevelVariable ||
            .enumConstant ||
            .typeAlias ||
            .functionTypeAlias) {
      return false;
    }
    final from = sources.offsetOf(
      path,
      node.element.range?.end ?? node.codeRange.start,
    );
    final to = sources.offsetOf(path, node.codeRange.end);
    final at = sources.offsetOf(path, pos);
    if (from == null || to == null || at == null) {
      return false;
    }
    final body = _bodyStart(content, from, to);
    return body != null && at >= body;
  }

  /// The offset of the first `{` or `=>` outside brackets in [content] between
  /// [from] and [to].
  static int? _bodyStart(String content, int from, int to) {
    var depth = 0;
    var i = from;
    while (i < to) {
      if (stringLiteralEnd(content, i) case final end?) {
        i = end;
        continue;
      }
      switch (content[i]) {
        case '(' || '[':
          depth++;
        case ')' || ']':
          depth--;
        case '{' when depth == 0:
          return i;
        case '=' when depth == 0 && i + 1 < to && content[i + 1] == '>':
          return i;
      }
      i++;
    }
    return null;
  }
}

/// Where a mention of a type escapes to: a type or extension that leaks it
/// only if it leaks itself, or the root, which always does.
final class _Carrier {
  const _Carrier.root() : key = null, extension = false;

  const _Carrier.of(DeclKey this.key, {required this.extension});

  final DeclKey? key;
  final bool extension;

  bool get isRoot => key == null;

  @override
  bool operator ==(Object other) =>
      other is _Carrier && other.key == key && other.extension == extension;

  @override
  int get hashCode => Object.hash(key, extension);
}
