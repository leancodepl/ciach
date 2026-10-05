import 'dart:io';

import 'package:ciach/src/candidates.dart';
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
/// A type is reachable when it is named outside a function body in an
/// importable file: in a signature, a field initializer, a supertype or a
/// typedef. A mention inside another type counts only if that type is
/// reachable too. An omitted return type is `dynamic`, so a body never hands
/// a type out.
final class ReachableTypes {
  ReachableTypes._(this._filesOf);

  static Future<ReachableTypes> find({
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
          // A file without an outline hands out every type it names.
        }
      }),
    );
    final positionsIn = <String, Set<Position>>{};
    for (final (_, typeRefs) in types.values) {
      for (final loc in typeRefs) {
        final path = SourceIndex.pathOf(loc.uri);
        if (outlines.containsKey(path) && api.isImportable(path)) {
          (positionsIn[path] ??= {}).add(loc.range.start);
        }
      }
    }
    await Future.wait(
      positionsIn.entries.map((entry) async {
        final positions = entry.value.toList();
        try {
          final ranges = await client.selectionRanges(
            File(entry.key).uri,
            positions,
          );
          for (final (i, range) in ranges.indexed) {
            if (range != null) {
              sources.cacheSelectionRange(entry.key, positions[i], range);
            }
          }
        } on LspRequestException {
          // Without syntax nodes no mention reads as in a body.
        }
      }),
    );

    // Each type's carriers: the types that hand it out if they are reachable.
    final carriersOf = <DeclKey, Set<DeclKey>>{};
    final reachable = <DeclKey>{};
    for (final MapEntry(:key, value: (type, typeRefs)) in types.entries) {
      final carriers = carriersOf[key] = {};
      if (api.exposes(key.path, key.name)) {
        reachable.add(key);
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
            reachable.add(key);
          case null:
            break;
        }
      }
    }

    final keys = types.keys.toList();
    final indexOf = {for (final (i, key) in keys.indexed) key: i};
    final internal = unreached(
      {for (var i = 0; i < keys.length; i++) i},
      [
        for (final key in reachable)
          (target: indexOf[key]!, enclosers: const []),
        for (final MapEntry(:key, value: carriers) in carriersOf.entries)
          for (final carrier in carriers)
            (target: indexOf[key]!, enclosers: [indexOf[carrier]!]),
      ],
    ).map((i) => keys[i]);

    final filesOf = {
      for (final key in internal)
        key: {
          key.path,
          for (final loc in types[key]!.$2) SourceIndex.pathOf(loc.uri),
        },
    };
    return ._(filesOf);
  }

  /// For each internal type, the files naming it, where its members are most
  /// likely used.
  final Map<DeclKey, Set<String>> _filesOf;

  /// Whether no other package can hold an instance of [member]'s type.
  bool isInternal(Candidate member) =>
      _filesOf.containsKey(member.containerKey);

  /// The files where [member] of an internal type is most likely used.
  Set<String> filesFor(Candidate member) => _filesOf[member.containerKey]!;

  /// Whether [member] is reachable only if its type is. Members of
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
    // A body is the syntax node that ends the declaration and opens it.
    final code = sources.code(path);
    for (
      var range = sources.selectionRangeAt(path, pos);
      range != null && node.codeRange.contains(range.range.start);
      range = range.parent
    ) {
      final start = sources.offsetOf(path, range.range.start);
      if (start != null &&
          range.range.end == node.codeRange.end &&
          range.range.start != node.codeRange.start &&
          _bodyOpener.matchAsPrefix(code, start) != null) {
        return true;
      }
    }
    return false;
  }
}

final _bodyOpener = RegExp(r'\{|=>|async\b|sync\b');

/// A carrier no type matches, so whatever it carries is reachable.
const _root = DeclKey('', '');
