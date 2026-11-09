/*
 * AI-Provenance:
 *   model: claude-opus-4-8
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/source/file_syntax.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/symbols.dart';
import 'package:ciach/src/util/paths.dart';

/// Flutter `StatefulWidget`/`State` conventions: recognizing the `State<Widget>`
/// pairing (so it isn't mistaken for an external use of the widget), and
/// coupling a dead widget's private `State` subclass to the widget's removal.
extension FlutterWidgets on FileSyntax {
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
      if (!isStateTypeArgument(loc)) {
        continue;
      }
      final path = loc.path;
      // The widget's own `createState` return type is inside the widget and
      // removed with it; only a pairing reference outside the widget points at
      // the separate State subclass.
      if (path == widget.path &&
          widget.outline.codeRange.contains(loc.range.start)) {
        continue;
      }
      final before = out.length;
      for (final (j, state) in candidates.indexed) {
        if (!state.isClassOrMixin ||
            state.path != path ||
            identical(state, widget) ||
            !state.outline.codeRange.contains(loc.range.start)) {
          continue;
        }
        if (_referencedOnlyWithin(
          refsByCandidate[j],
          widget.outline.codeRange,
          widget.path,
        )) {
          out.add((
            filePath: relativePosix(state.path, rootPath),
            kind: state.reportedKind,
            isClauseEntry: false,
            range: state.outline.codeRange.toDeclarationRange,
            fullRange: state.outline.range.toDeclarationRange,
            cut: null,
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
    Range enclosing,
    String path,
  ) => refs.every(
    (loc) =>
        isDocReference(loc) ||
        (loc.path == path && enclosing.contains(loc.range.start)),
  );
}
