/// A use of `target` from text inside each of `enclosers` (a method and its
/// class, say): removing any of them deletes it, so it is live once all are.
/// None = a root.
typedef Use = ({int target, Iterable<int> enclosers});

/// The [nodes] no root reaches through [uses]; unlike the `transitive`
/// rounds, this includes cycles.
Set<int> unreached(Set<int> nodes, Iterable<Use> uses) {
  final live = <int>{};
  final queue = <int>[];
  void mark(int node) {
    if (nodes.contains(node) && live.add(node)) {
      queue.add(node);
    }
  }

  final targets = <int>[];
  final deadEnclosers = <int>[];
  final enclosed = <int, List<int>>{};
  for (final (:target, :enclosers) in uses) {
    if (!nodes.contains(target)) {
      continue;
    }
    final dead = enclosers.where(nodes.contains).toSet();
    if (dead.isEmpty) {
      mark(target);
      continue;
    }
    final use = targets.length;
    targets.add(target);
    deadEnclosers.add(dead.length);
    for (final encloser in dead) {
      enclosed.putIfAbsent(encloser, () => []).add(use);
    }
  }

  while (queue.isNotEmpty) {
    for (final use in enclosed[queue.removeLast()] ?? const <int>[]) {
      if (--deadEnclosers[use] == 0) {
        mark(targets[use]);
      }
    }
  }
  return nodes.difference(live);
}
