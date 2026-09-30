/// [count] and the matching form of a noun: `plural(3, 'file')` is `3 files`.
/// [other] defaults to [one] plus `s`.
String plural(int count, String one, [String? other]) =>
    '$count ${pluralWord(count, one, other)}';

/// [one] if [count] is 1, else [other] (by default [one] plus `s`).
String pluralWord(int count, String one, [String? other]) =>
    count == 1 ? one : other ?? '${one}s';
