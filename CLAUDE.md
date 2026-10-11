# CHANGELOG.md

End every entry with a link to its pull request, never to an issue:
`([#N](https://github.com/leancodepl/ciach/pull/N))`. Before committing an
entry, run `dart run tool/check_changelog.dart --pr N`; CI runs the same check.

# String literals

Write a string as one literal. Use a `'''` multi-line string for text with
interior newlines (expected output, fixtures). Keep adjacent string literals
only in two places: `test(...)` and `group(...)` descriptions, which
`dart format` keeps compact in that form alone, and strings whose joined line
would run past 120 columns. Never wrap with `+`. Option help texts in
`lib/src/cli/args.dart` are plain sentences with no `\n`; the parser wraps
them (`usageLineLength`).

# Dot shorthands

Use a dot shorthand wherever the context type lets you: `.new(path, c)`
rather than `DeclKey(path, c)`, `.plain` rather than `Style.plain`, including
inside lambdas whose return type the context already fixes. Never replace a
shorthand with the full type name. Annotation arguments are the exception:
`@Timeout(Duration(minutes: 5))` stays, since `package:test` parses it with
an evaluator of its own that knows no shorthands. The `prefer_dot_shorthand`
rule in `tool/ciach_lints` enforces all of this.

# Nullable chains

Use `x?.let(f)` from `lib/src/extensions.dart` rather than
`switch (x) { final v? => f(v), null => null }` or `x == null ? null : f(x)`,
and `x?.let(f) ?? d` rather than `x == null ? d : f(x)`. Read as much as
possible before the `let`, in the null-aware chain: `x?.y.let(f)`, not
`x?.let((it) => f(it.y))`.
