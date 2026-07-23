/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/candidates.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// The `State<` immediately preceding a type argument, with a token boundary
/// before `State` so `MyState<…>`/`FooState<…>` don't match.
final _statePrefix = RegExp(r'(?:^|[^A-Za-z0-9_$])State<\s*$');

/// The `>` that closes a single `State<…>` type argument.
final _stateSuffix = RegExp(r'^\s*>');

/// Flutter `StatefulWidget`/`State` conventions: recognizing the `State<Widget>`
/// pairing (so it isn't mistaken for an external use of the widget), and
/// coupling a dead widget's private `State` subclass to the widget's removal.
extension FlutterWidgets on SourceIndex {
  /// Whether [loc] is the class name [className] appearing as the sole type
  /// argument of `State<…>`, e.g. `class _FooState extends State<Foo>`.
  ///
  /// `State<Foo>` can only ever denote the state object of the `Foo` widget, so
  /// it never means `Foo` itself is used elsewhere.
  bool isStatePairingReference(String className, Location loc) {
    final start = loc.range.start;
    final end = loc.range.end;
    if (start.line != end.line) {
      return false;
    }
    final fileLines = lines(SourceIndex.pathOf(loc.uri));
    if (start.line < 0 || start.line >= fileLines.length) {
      return false;
    }
    final line = fileLines[start.line];
    if (start.character < 0 ||
        end.character > line.length ||
        start.character > end.character) {
      return false;
    }
    if (line.substring(start.character, end.character) != className) {
      return false;
    }
    return _statePrefix.hasMatch(line.substring(0, start.character)) &&
        _stateSuffix.hasMatch(line.substring(end.character));
  }

  /// The extra spans to remove alongside a dead [widget] class: the paired
  /// private `State<Widget>` subclass, when there is exactly one and it is used
  /// only from within the widget (via `createState`). Returns an empty list for
  /// a plain class, or a StatefulWidget whose State is referenced elsewhere.
  ///
  /// Removing the widget on its own would leave
  /// `class _S extends State<Widget>` referring to a now-deleted type — a build
  /// break — so the State is coupled to the widget's removal, but it is not
  /// itself reported.
  List<CoupledRemoval> pairedStateRemovals(
    Candidate widget,
    List<Location> widgetRefs,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final out = <CoupledRemoval>[];
    for (final loc in widgetRefs) {
      if (!isStatePairingReference(widget.symbol.name, loc) ||
          SourceIndex.pathOf(loc.uri) != widget.path) {
        continue;
      }
      // The widget's own `createState` return type is inside the widget and
      // removed with it; only a pairing reference outside the widget points at
      // the separate State subclass.
      if (loc.range.start.within(widget.symbol)) {
        continue;
      }
      for (var j = 0; j < candidates.length; j++) {
        final state = candidates[j];
        if (state.symbol.kind != .class$ ||
            state.path != widget.path ||
            identical(state, widget) ||
            !loc.range.start.within(state.symbol)) {
          continue;
        }
        if (_referencedOnlyWithin(
          refsByCandidate[j],
          widget.symbol,
          widget.path,
        )) {
          out.add((
            filePath: relativePosix(state.path, rootPath),
            range: state.symbol.declarationRange,
          ));
        }
        break;
      }
    }
    return out;
  }

  /// Whether every *code* reference in [refs] lies within [enclosing] in [path]
  /// — used to confirm a paired State subclass is reachable only from its
  /// widget. Doc-comment links are ignored: documentation never keeps code
  /// alive, so it must not block coupling.
  bool _referencedOnlyWithin(
    List<Location> refs,
    DocumentSymbol enclosing,
    String path,
  ) => refs.every(
    (loc) =>
        isDocReference(loc) ||
        (SourceIndex.pathOf(loc.uri) == path &&
            loc.range.start.within(enclosing)),
  );
}
