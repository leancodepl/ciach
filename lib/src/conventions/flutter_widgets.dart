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
import 'package:collection/collection.dart';

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
    final widgetRange = widget.outline.codeRange;
    bool holds(Candidate state, Location loc) =>
        state.isClassOrMixin &&
        state.path == loc.path &&
        state.outline.codeRange.contains(loc.range.start);
    // The State subclass that holds each pairing reference, with its index,
    // or `null` when no candidate holds it. The widget's own `createState`
    // return type is inside the widget and removed with it; only a pairing
    // reference outside the widget points at the separate State subclass.
    final states = [
      for (final loc in widgetRefs)
        if (isStateTypeArgument(loc) &&
            !(loc.path == widget.path && widgetRange.contains(loc.range.start)))
          candidates.indexed.firstWhereOrNull((found) => holds(found.$2, loc)),
    ];
    final removals = <CoupledRemoval>[
      for (final (j, state) in states.nonNulls)
        if (_referencedOnlyWithin(refsByCandidate[j], widgetRange, widget.path))
          (
            filePath: relativePosix(state.path, rootPath),
            kind: state.reportedKind,
            isClauseEntry: false,
            range: state.outline.codeRange.toDeclarationRange,
            fullRange: state.outline.range.toDeclarationRange,
            cut: null,
          ),
    ];
    return (removals: removals, blocked: removals.length < states.length);
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
