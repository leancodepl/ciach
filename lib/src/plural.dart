/// [count] with the form of a noun that fits it: `plural(3, 'file', 'files')`
/// is `3 files`.
String plural(int count, String one, String other) =>
    '$count ${pluralWord(count, one, other)}';

/// [one] if [count] is 1, else [other].
String pluralWord(int count, String one, String other) =>
    count == 1 ? one : other;
