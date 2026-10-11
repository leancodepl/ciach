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
