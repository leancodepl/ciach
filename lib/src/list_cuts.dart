/// Cuts items out of a comma-separated list, such as the variables of
/// `int a = 1, b = 2` or the types of `implements A, B`.
library;

import 'package:pro_lsp/pro_lsp.dart' show Range;

/// Returns each longest run of adjacent [items] that [isCut] accepts: its
/// index range `[i, j)`, and the range that removes it.
///
/// A run goes with the comma after it, or, when it ends the list, with the
/// comma before it. The range is `null` for a run that is the whole list,
/// since what goes then depends on the list.
Iterable<(int, int, Range?)> listCuts(
  List<Range> items,
  bool Function(Range item) isCut,
) sync* {
  var i = 0;
  while (i < items.length) {
    if (!isCut(items[i])) {
      i++;
      continue;
    }
    var j = i + 1;
    while (j < items.length && isCut(items[j])) {
      j++;
    }
    yield (i, j, _cutOf(items, i, j));
    i = j;
  }
}

/// Returns the range that removes items `[i, j)` of [items]; see [listCuts].
Range? _cutOf(List<Range> items, int i, int j) {
  if (j < items.length) {
    return Range(start: items[i].start, end: items[j].start);
  }
  if (i > 0) {
    return Range(start: items[i - 1].end, end: items[j - 1].end);
  }
  return null;
}
