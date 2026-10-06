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

  // waitingOn[n]: the uses written inside n, while n is not proven live yet.
  // A use counts only once every node it is written inside is proven live.
  final waitingOn = <int, List<_PendingUse>>{};
  for (final (:target, :enclosers) in uses) {
    if (!maybeDead.contains(target)) {
      continue;
    }
    final deadEnclosers = enclosers.where(maybeDead.contains).toSet();
    if (deadEnclosers.isEmpty) {
      markLive(target);
      continue;
    }
    final pending = _PendingUse(target, deadEnclosers.length);
    for (final encloser in deadEnclosers) {
      waitingOn.putIfAbsent(encloser, () => []).add(pending);
    }
  }

  // Worklist propagation, as in linear-time Horn-SAT: each use is the rule
  // "all enclosers live -> target live", and each node is popped once.
  while (queue.isNotEmpty) {
    final node = queue.removeLast();
    for (final pending in waitingOn[node] ?? const <_PendingUse>[]) {
      if (--pending.deadEnclosers == 0) {
        markLive(pending.target);
      }
    }
  }
  return maybeDead.difference(live);
}

final class _PendingUse {
  _PendingUse(this.target, this.deadEnclosers);

  final int target;
  int deadEnclosers;
}
