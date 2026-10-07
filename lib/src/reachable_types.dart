import 'dart:io';

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/lsp/lsp_client.dart';
import 'package:ciach/src/lsp/outline.dart';
import 'package:ciach/src/public_api.dart';
import 'package:ciach/src/reachability.dart';
import 'package:ciach/src/reference_fetch.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
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
    required ReferenceFetch fetch,
    required PublicApi api,
    required List<Candidate> candidates,
    required List<List<Location>> refs,
  }) async {
    final types = <DeclKey, (Candidate, List<Location>)>{
      for (final (i, candidate) in candidates.indexed)
        if (_isType(candidate)) candidate.key: (candidate, refs[i]),
    };
    final positionsIn = <String, Set<Position>>{};
    for (final (_, typeRefs) in types.values) {
      for (final loc in typeRefs) {
        final path = SourceIndex.pathOf(loc.uri);
        if (sources.scannedPaths.contains(path) && api.isImportable(path)) {
          (positionsIn[path] ??= {}).add(loc.range.start);
        }
      }
    }
    final outlines = <String, Outline>{};
    await Future.wait(
      positionsIn.keys.map((path) async {
        try {
          outlines[path] = await client.outline(File(path).uri);
        } on LspRequestException {
          // A file without an outline hands out every type it names.
        }
      }),
    );
    await fetch.fetchSelectionRanges(client, positionsIn);

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
          (target: indexOf[key]!, containers: const []),
        for (final MapEntry(:key, value: carriers) in carriersOf.entries)
          for (final carrier in carriers)
            (target: indexOf[key]!, containers: [indexOf[carrier]!]),
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
    final top = unit.childAt(pos);
    if (top == null) {
      return null;
    }
    final kind = top.element.kind;
    if (kind case .class$ || .mixin || .enum$ || .extension || .extensionType) {
      final member = top.childAt(pos);
      if (member != null && _hidesIn(member, top, path, pos, sources)) {
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
    return _hidesIn(top, null, path, pos, sources) ? null : _root;
  }

  /// Whether a mention at [pos] in the function-like [node] stays inside it:
  /// it sits in the body, and nothing the signature hands out is `dynamic`.
  static bool _hidesIn(
    Outline node,
    Outline? owner,
    String path,
    Position pos,
    SourceIndex sources,
  ) {
    final element = node.element;
    if (element.kind
        case .field ||
            .topLevelVariable ||
            .enumConstant ||
            .typeAlias ||
            .functionTypeAlias) {
      return false;
    }
    final from = sources.offsetOf(path, node.codeRange.start);
    if (from == null) {
      return false;
    }
    final body = _bodyStart(node, path, pos, sources);
    if (body == null) {
      return false;
    }
    final returnsDynamic =
        (element.kind == .function ||
            element.kind == .method ||
            element.kind == .getter) &&
        ((element.returnType ?? '').isEmpty || element.returnType == 'dynamic');
    return !returnsDynamic &&
        !_dynamic.hasMatch(sources.code(path).substring(from, body)) &&
        (element.typeParameters ?? '').isEmpty &&
        (owner?.element.typeParameters ?? '').isEmpty &&
        !_hasUntypedParameter(element.parameters);
  }

  /// Where the body of [node] that holds [pos] starts: the syntax node that
  /// ends the declaration and opens with `{`, `=>`, `async` or `sync`.
  static int? _bodyStart(
    Outline node,
    String path,
    Position pos,
    SourceIndex sources,
  ) {
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
        return start;
      }
    }
    return null;
  }

  /// Whether a parameter in [parameters], as written, has no type.
  static bool _hasUntypedParameter(String? parameters) {
    if (parameters == null) {
      return false;
    }
    var flat = parameters.substring(1, parameters.length - 1);
    while (flat.contains(_nested)) {
      flat = flat.replaceAll(_nested, '');
    }
    return flat.split(',').any((part) {
      final declared = part
          .split('=')
          .first
          .replaceAll(_parameterNoise, '')
          .trim();
      return _identifier.hasMatch(declared);
    });
  }
}

/// An innermost `(…)` or `<…>`, such as a function type's parameters or a
/// type's arguments.
final _nested = RegExp(r'\([^()]*\)|<[^<>]*>');
final _parameterNoise = RegExp(r'[{}\[\]]|\b(?:required|covariant|final)\b');
final _identifier = RegExp(r'^[\w$]+$');

/// Types through which a caller can invoke any member.
final _dynamic = RegExp(r'\b(?:dynamic|Function|var)\b');

final _bodyOpener = RegExp(r'\{|=>|async\b|sync\b');

/// A carrier no type matches, so whatever it carries is reachable.
const _root = DeclKey('', '');
