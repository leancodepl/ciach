/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/model/finder_result.dart';
import 'package:ciach/src/model/unused_declaration.dart';
import 'package:ciach/src/settle/removable.dart';
import 'package:ciach/src/util/paths.dart';

/// Returns the classes, mixins and extensions that `--remove` leaves with an
/// empty body: each of their members is a removable finding in [candidateOf],
/// but the declaration itself is not a finding, because other code still
/// uses it.
List<EmptiedContainer> emptiedContainers(
  List<Candidate> candidates,
  Map<UnusedDeclaration, int> candidateOf,
  String rootPath,
) {
  final removable = removableIndices(candidateOf);
  final members = removableMembers(candidates, removable);
  return [
    for (final MapEntry(key: container, value: (:outline, :removable))
        in members.entries)
      if (outline?.children.length == removable &&
          // An extension type keeps its representation field, like `value` in
          // `extension type Id(int value)`. The outline leaves that field
          // out, so the type would wrongly look emptied.
          outline!.element.kind != .extensionType)
        (
          filePath: relativePosix(container.path, rootPath),
          name: container.name,
        ),
  ]..sort(
    (a, b) => switch (a.filePath.compareTo(b.filePath)) {
      0 => a.name.compareTo(b.name),
      final byFile => byFile,
    },
  );
}
