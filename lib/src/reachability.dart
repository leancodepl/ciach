/// A use of `target` from text inside each of `enclosers` (a method and its
/// class, say): removing any of them deletes it, so it is live once all are.
/// None = a root.
typedef Use = ({int target, Iterable<int> enclosers});

/// The [maybeDead] nodes no root reaches through [uses]; unlike the
/// `transitive` rounds, this includes cycles.
Set<int> unreached(Set<int> maybeDead, Iterable<Use> uses) {
  final live = <int>{};
  final queue = <int>[];
  void markLive(int node) {
    if (maybeDead.contains(node) && live.add(node)) {
      queue.add(node);
    }
  }

  // usesInside[n]: the uses whose text lies inside maybe-dead node n.
  final usesInside = <int, List<_PendingUse>>{};
  for (final (:target, :enclosers) in uses) {
    if (!maybeDead.contains(target)) {
      continue;
    }
    final maybeDeadEnclosers = enclosers.where(maybeDead.contains).toSet();
    if (maybeDeadEnclosers.isEmpty) {
      markLive(target);
      continue;
    }
    final pending = _PendingUse(target, maybeDeadEnclosers.length);
    for (final encloser in maybeDeadEnclosers) {
      usesInside.putIfAbsent(encloser, () => []).add(pending);
    }
  }

  // Worklist propagation, as in linear-time Horn-SAT: each use is the rule
  // "all enclosers live -> target live", and each node is popped once.
  while (queue.isNotEmpty) {
    final node = queue.removeLast();
    for (final pending in usesInside[node] ?? const <_PendingUse>[]) {
      if (--pending.maybeDeadEnclosers == 0) {
        markLive(pending.target);
      }
    }
  }
  return maybeDead.difference(live);
}

/// A use with [maybeDeadEnclosers] of its enclosers not yet proven live.
final class _PendingUse {
  _PendingUse(this.target, this.maybeDeadEnclosers);

  final int target;
  int maybeDeadEnclosers;
}
