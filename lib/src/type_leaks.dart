import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/comment_stripping.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/public_api.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:collection/collection.dart';
import 'package:pro_lsp/pro_lsp.dart' show Location, Position;

/// Unexported types another package may still hold an instance of.
///
/// A type leaks when it is named outside a function body in an importable
/// file: in a signature, a field initializer, a supertype or a typedef. A
/// mention inside another type counts only if that type leaks too. An
/// omitted return type is `dynamic`, so a body never leaks a type.
final class TypeLeaks {
  TypeLeaks._(this._filesOf);

  static Future<TypeLeaks> find({
    required LspClient client,
    required SourceIndex sources,
    required PublicApi api,
    required List<Candidate> candidates,
    required List<List<Location>> refs,
  }) async {
    final types = <DeclKey, (Candidate, List<Location>)>{
      for (final (i, candidate) in candidates.indexed)
        if (_isType(candidate)) candidate.key: (candidate, refs[i]),
    };
    final paths = {
      for (final (_, typeRefs) in types.values)
        for (final loc in typeRefs) SourceIndex.pathOf(loc.uri),
    }.where(sources.scannedPaths.contains);
    final outlines = <String, Outline>{};
    await Future.wait(
      paths.map((path) async {
        try {
          outlines[path] = await client.outline(File(path).uri);
        } on LspRequestException {
          // A file without an outline reads as leaking every type it names.
        }
      }),
    );

    // Each type's carriers: the types whose leak would leak it.
    final carriersOf = <DeclKey, Set<DeclKey>>{};
    final leaking = <DeclKey>{};
    for (final MapEntry(:key, value: (type, typeRefs)) in types.entries) {
      final carriers = carriersOf[key] = {};
      if (api.exposes(key.path, key.name)) {
        leaking.add(key);
      }
      for (final loc in typeRefs) {
        final path = SourceIndex.pathOf(loc.uri);
        final pos = loc.range.start;
        if (!api.isImportable(path) ||
            (path == type.path && type.outline.range.contains(pos)) ||
            sources.isDocReference(loc)) {
          continue;
        }
        switch (_carrierAt(outlines[path], path, pos, sources, api)) {
          case final carrier? when types.containsKey(carrier):
            carriers.add(carrier);
          case _?:
            leaking.add(key);
          case null:
            break;
        }
      }
    }

    final keys = types.keys.toList();
    final indexOf = {for (final (i, key) in keys.indexed) key: i};
    final sealed = unreached(
      {for (var i = 0; i < keys.length; i++) i},
      [
        for (final key in leaking) (target: indexOf[key]!, enclosers: const []),
        for (final MapEntry(:key, value: carriers) in carriersOf.entries)
          for (final carrier in carriers)
            (target: indexOf[key]!, enclosers: [indexOf[carrier]!]),
      ],
    ).map((i) => keys[i]);

    final filesOf = {
      for (final key in sealed)
        key: {
          key.path,
          for (final loc in types[key]!.$2) SourceIndex.pathOf(loc.uri),
        },
    };
    return ._(filesOf);
  }

  /// For each sealed type, the files naming it, where its members are most
  /// likely used.
  final Map<DeclKey, Set<String>> _filesOf;

  /// Whether no other package can hold an instance of [member]'s type.
  bool isSealed(Candidate member) => _filesOf.containsKey(member.containerKey);

  /// The files where [member] of a sealed type is most likely used.
  Set<String> filesFor(Candidate member) => _filesOf[member.containerKey]!;

  /// Whether [member] is reachable only if its type leaks. Members of
  /// extensions are reached only by importing them.
  static bool isGated(Candidate member) =>
      member.container != null &&
      member.containerOutline?.element.kind != .extension &&
      !isPrivateName(member.symbol.name);

  static bool _isType(Candidate candidate) =>
      candidate.container == null &&
      typeLikeKinds.contains(candidate.symbol.kind) &&
      !candidate.isExtension;

  /// The type the reference at [pos] hands its type to, [_root] when it
  /// hands it to everyone, or `null` when it sits in a body, a directive or
  /// an extension no other package can import.
  static DeclKey? _carrierAt(
    Outline? unit,
    String path,
    Position pos,
    SourceIndex sources,
    PublicApi api,
  ) {
    if (unit == null) {
      return _root;
    }
    final top = _childAt(unit, pos);
    if (top == null) {
      return null;
    }
    final kind = top.element.kind;
    if (kind case .class$ || .mixin || .enum$ || .extension || .extensionType) {
      final member = _childAt(top, pos);
      if (member != null && _inBody(member, path, pos, sources)) {
        return null;
      }
      if (kind != .extension) {
        return DeclKey(path, top.element.name);
      }
      return !top.element.isUnnamedExtension &&
              api.exposes(path, top.element.name)
          ? _root
          : null;
    }
    return _inBody(top, path, pos, sources) ? null : _root;
  }

  static Outline? _childAt(Outline parent, Position pos) =>
      parent.children.firstWhereOrNull((child) => child.range.contains(pos));

  /// Whether [pos] lies in the body of the function-like [node].
  static bool _inBody(
    Outline node,
    String path,
    Position pos,
    SourceIndex sources,
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
    final body = _bodyStart(sources.code(path), from, to);
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

/// A carrier no type matches, so whatever it carries leaks.
const _root = DeclKey('', '');
