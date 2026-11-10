/// Cuts items out of a comma-separated list, such as the variables of
/// `int a = 1, b = 2` or the types of `implements A, B`.
library;

import 'package:pro_lsp/pro_lsp.dart' show Range;

/// Returns each group of adjacent [items] that [isRemoved] accepts: its index
/// range `[i, j)` and the range that deletes it.
///
/// A group is cut out with the comma after it: in `a, b, c`, removing `b`
/// deletes `b, `. A group that ends the list goes with the comma before it:
/// removing `c` deletes `, c`. The range is `null` when the group is the whole
/// list, because then the caller deletes the whole statement or clause instead.
Iterable<(int, int, Range?)> listCuts(
  List<Range> items,
  bool Function(Range item) isRemoved,
) sync* {
  var i = 0;
  while (i < items.length) {
    if (!isRemoved(items[i])) {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < items.length && isRemoved(items[j])) {
      j++;
    }
    yield (i, j, _cutOf(items, i, j));
    i = j;
  }
}

/// Returns the range that removes items `[i, j)` of [items]; see [listCuts].
Range? _cutOf(List<Range> items, int i, int j) {
  if (j < items.length) {
    return .new(start: items[i].start, end: items[j].start);
  }
  if (i > 0) {
    return .new(start: items[i - 1].end, end: items[j - 1].end);
  }
  return null;
}
