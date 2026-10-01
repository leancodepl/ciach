/// One use of a declaration: of `target`, from a site that only survives if
/// every one of its `enclosers` does. No enclosers is a use from live code.
typedef Use = ({int target, Iterable<int> enclosers});

/// The [nodes] no live code reaches: the sweep of a mark-and-sweep over the
/// reference graph.
///
/// Every node starts dead. A use with no enclosers marks its target live, and
/// a node marked live frees the uses it encloses; a use whose enclosers are
/// all live marks its target live in turn. Unlike deleting what nothing
/// references, round after round, this also sweeps a cycle: its members only
/// reach each other, so none is ever marked. Linear in the uses and their
/// enclosers, and independent of their order.
Set<int> unreached(Set<int> nodes, Iterable<Use> uses) {
  final live = <int>{};
  final queue = <int>[];
  void mark(int node) {
    if (nodes.contains(node) && live.add(node)) {
      queue.add(node);
    }
  }

  // Per use, how many of its enclosers are still dead; per node, the uses it
  // encloses.
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
