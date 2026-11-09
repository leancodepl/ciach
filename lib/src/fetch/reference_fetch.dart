import 'package:ciach/src/analysis/resolved_files.dart';
import 'package:ciach/src/collect/candidates.dart';
import 'package:ciach/src/collect/problems.dart';
import 'package:ciach/src/source/locations.dart';
import 'package:ciach/src/source/symbols.dart';

const _uncheckedDeclaration = 'Could not find references; kept.';

const _noDeclaration =
    'The analyzer found no declaration whose name starts here.';

/// The references of each of [candidates], from [files] after they resolved
/// every file under the analysis root. A candidate whose declaration the
/// analyzer doesn't find is left out, so it is never reported.
({List<Candidate> checked, List<List<Location>> refs}) referencesOf(
  ResolvedFiles files,
  List<Candidate> candidates,
) {
  final found = [
    for (final candidate in candidates)
      if (_referencesOf(files, candidate) case final refs?)
        (candidate: candidate, refs: refs),
  ];
  return (
    checked: [for (final (:candidate, refs: _) in found) candidate],
    refs: [for (final (candidate: _, :refs) in found) refs],
  );
}

List<Location>? _referencesOf(ResolvedFiles files, Candidate candidate) {
  final start = candidate.outline.nameRange.start;
  final refs = files.referencesTo(candidate.path, start);
  if (refs == null) {
    recordProblem(
      _uncheckedDeclaration,
      _noDeclaration,
      path: candidate.path,
      position: start,
      name: candidate.outline.element.qualifiedName(candidate.container),
    );
  }
  return refs;
}
