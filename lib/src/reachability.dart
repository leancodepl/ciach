/// A use of `target`, written inside each of `containers` (a method and its
/// class, say). Removing any container removes the use, so it counts only
/// once all of them are live. No containers: a use from live code.
typedef Use = ({int target, Iterable<int> containers});

/// The [dead] nodes that stay dead: each starts dead, and a use whose
/// containers are all live revives its target. Unlike the `transitive`
/// rounds, this leaves cycles dead.
Set<int> unreached(Set<int> dead, Iterable<Use> uses) {
  final live = <int>{};
  final revived = <int>[];
  void revive(int node) {
    if (dead.contains(node) && live.add(node)) {
      revived.add(node);
    }
  }

  // For each dead node, the uses written inside it.
  final usesInside = <int, List<_ContainedUse>>{};
  for (final (:target, :containers) in uses) {
    if (!dead.contains(target)) {
      continue;
    }
    final deadContainers = containers.where(dead.contains).toSet();
    if (deadContainers.isEmpty) {
      revive(target);
      continue;
    }
    final use = _ContainedUse(target, deadContainers.length);
    for (final container in deadContainers) {
      usesInside.putIfAbsent(container, () => []).add(use);
    }
  }

  // Worklist propagation, as in linear-time Horn-SAT: each revived node is
  // taken once, and a use counts when its last dead container is revived.
  while (revived.isNotEmpty) {
    final node = revived.removeLast();
    for (final use in usesInside[node] ?? const <_ContainedUse>[]) {
      if (--use.deadContainers == 0) {
        revive(use.target);
      }
    }
  }
  return dead.difference(live);
}

/// A use of [target] with [deadContainers] containers not revived yet.
final class _ContainedUse {
  _ContainedUse(this.target, this.deadContainers);

  final int target;
  int deadContainers;
}
