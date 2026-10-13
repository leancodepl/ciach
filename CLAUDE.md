# CHANGELOG.md

End every entry with a link to its pull request, never to an issue:
`([#N](https://github.com/leancodepl/ciach/pull/N))`. Before committing an
entry, run `dart run tool/check_changelog.dart --pr N`; CI runs the same check.

Write an entry for the people who use ciach. In one to three short, plain
sentences, say what was added, fixed or changed, as they will see it. For a
fix, say what went wrong before. Leave out how it was implemented: no class or
method names, internal terms or reasoning about the code.

The same goes for README.md and other user docs: describe what ciach does and
how to use it, in short, easy-to-follow sentences, not how it works inside.

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
and `x?.let(f) ?? d` rather than `x == null ? d : f(x)`, also for a value a
null check cannot promote: `a.b?.let(f) ?? d`, never `a.b == null ? d :
f(a.b!)`. Read as much as possible before the `let`, in the null-aware chain:
`x?.y.let(f)`, not `x?.let((it) => f(it.y))`.
