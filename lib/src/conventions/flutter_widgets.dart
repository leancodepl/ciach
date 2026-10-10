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
import 'package:ciach/src/lsp/semantic_tokens.dart';
import 'package:ciach/src/models.dart';
import 'package:ciach/src/paths.dart';
import 'package:ciach/src/reference_kinds.dart';
import 'package:ciach/src/source_index.dart';
import 'package:ciach/src/symbols.dart';
import 'package:pro_lsp/pro_lsp.dart' show DocumentSymbol, Location;

/// Flutter `StatefulWidget`/`State` conventions: recognizing the `State<Widget>`
/// pairing (so it isn't mistaken for an external use of the widget), and
/// coupling a dead widget's private `State` subclass to the widget's removal.
extension FlutterWidgets on SourceIndex {
  /// Whether [loc] is [className] as the sole type argument in an
  /// `extends State<…>` clause. That reference is not a use of the widget.
  bool isStatePairingReference(String className, Location loc) {
    final path = SourceIndex.pathOf(loc.uri);
    final position = loc.range.start;
    final tokens = semanticTokens(path);
    final argument = selectionRangeAt(path, position);
    final arguments = argument?.parent;
    final type = arguments?.parent;
    final clause = type?.parent;
    if (tokens == null ||
        argument == null ||
        arguments == null ||
        type == null ||
        clause == null) {
      return false;
    }
    final name = tokens.startingAt(position);
    if (name == null || name.text != className) {
      return false;
    }
    // `State<Foo>`, not `State<Foo, Bar>`.
    if (tokens.between(arguments.range.start, arguments.range.end).length !=
        1) {
      return false;
    }
    final state = tokens.startingAt(type.range.start);
    final keyword = tokens.startingAt(clause.range.start);
    return state != null &&
        state.type == 'class' &&
        state.text == 'State' &&
        keyword != null &&
        keyword.isKeyword &&
        keyword.text == 'extends';
  }

  /// The extra spans to remove alongside a dead [widget] class: each
  /// `State<Widget>` subclass, in any file, used only from within the widget
  /// (via `createState`). Returns an empty list for
  /// a plain class.
  ///
  /// Removing the widget on its own would leave
  /// `class _S extends State<Widget>` referring to a now-deleted type — a build
  /// break — so the State is coupled to the widget's removal, but it is not
  /// itself reported. A State that can't be coupled (used elsewhere) makes
  /// the widget `blocked`.
  ({List<CoupledRemoval> removals, bool blocked}) pairedStateRemovals(
    Candidate widget,
    List<Location> widgetRefs,
    List<Candidate> candidates,
    List<List<Location>> refsByCandidate,
    String rootPath,
  ) {
    final out = <CoupledRemoval>[];
    var blocked = false;
    for (final loc in widgetRefs) {
      if (!isStatePairingReference(widget.symbol.name, loc)) {
        continue;
      }
      final path = SourceIndex.pathOf(loc.uri);
      // The widget's own `createState` return type is inside the widget and
      // removed with it; only a pairing reference outside the widget points at
      // the separate State subclass.
      if (path == widget.path && loc.range.start.within(widget.symbol)) {
        continue;
      }
      final before = out.length;
      for (var j = 0; j < candidates.length; j++) {
        final state = candidates[j];
        if (state.symbol.kind != .class$ ||
            state.path != path ||
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
            kind: state.symbol.kind,
            range: state.outline.codeRange.toDeclarationRange,
            fullRange: state.outline.range.toDeclarationRange,
          ));
        }
        break;
      }
      blocked |= out.length == before;
    }
    return (removals: out, blocked: blocked);
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
