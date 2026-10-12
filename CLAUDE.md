# CHANGELOG.md

End every entry with a link to its pull request, never to an issue:
`([#N](https://github.com/leancodepl/ciach/pull/N))`. Before committing an
entry, run `dart run tool/check_changelog.dart --pr N`; CI runs the same check.

# String literals

Write a string as one literal. Use a `'''` multi-line string for text with
interior newlines (expected output, fixtures); the `prefer_multiline_string`
rule in `tool/ciach_lints` flags a single-line literal with two or more
interior `\n` escapes and offers a quick-fix that rewrites it. Keep adjacent
string literals only in two places: `test(...)` and `group(...)` descriptions,
which `dart format` keeps compact in that form alone, and strings whose joined
line would run past 120 columns. Never wrap with `+`. Option help texts in
`lib/src/cli/args.dart` are plain sentences with no `\n`; the parser wraps
them (`usageLineLength`).

# Dot shorthands

Use a dot shorthand wherever the context type lets you: `.new(path, c)`
rather than `DeclKey(path, c)`, `.plain` rather than `Style.plain`, including
inside lambdas whose return type the context already fixes. Never replace a
shorthand with the full type name.

# Nullable chains

Use `x?.let(f)` from `lib/src/extensions.dart` rather than
`switch (x) { final v? => f(v), null => null }` or `x == null ? null : f(x)`,
and `x?.let(f) ?? d` rather than `x == null ? d : f(x)`. Read as much as
possible before the `let`, in the null-aware chain: `x?.y.let(f)`, not
`x?.let((it) => f(it.y))`.

# File size

Keep every Dart file under 500 lines (`wc -l`); the `file_length` rule in
`tool/ciach_lints` flags a longer one, and `dart analyze` fails on it. Past
about 400 lines, split before adding more, along a seam the file already
has; never grow one past the limit and never add `// ignore` for the rule.
List the largest files with
`find lib bin test tool -name '*.dart' | xargs wc -l | sort -rn | head`.

- A test file: one file per `group` or per scenario fixture, in a directory
  named after the unit under test (`test/finder/widgets_test.dart`), with the
  shared setup, runners and fixtures as documented top-level functions in
  `test/support/<unit>.dart`. Every file keeps its own `main`, `@Timeout`
  and setup calls, so it runs on its own and in parallel with the others.
- A library: the code a file's main class only calls into, as a class or a
  set of functions in its own file (`transitive_sweep.dart` out of
  `settler.dart`, `removal_spans.dart` out of `remover.dart`,
  `lsp/exceptions.dart` out of `lsp/lsp_client.dart`). Move the doc comments
  with it, and update the importers; never re-export the moved names from
  the old file, and never use `part`.
- Never split mid-concept: a class stays in one file, a `group` in one test
  file. A table that is long by nature, like the option enum in
  `lib/src/cli/args.dart`, stays whole under the limit.
