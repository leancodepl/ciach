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

Use `x?.let(f)` from `lib/src/util/extensions.dart` rather than
`switch (x) { final v? => f(v), null => null }` or `x == null ? null : f(x)`,
and `x?.let(f) ?? d` rather than `x == null ? d : f(x)`, also for a value a
null check cannot promote: `a.b?.let(f) ?? d`, never `a.b == null ? d :
f(a.b!)`. Read as much as possible before the `let`, in the null-aware chain:
`x?.y.let(f)`, not `x?.let((it) => f(it.y))`.

# Layout

`lib/src/` is organized by the stage of a scan: `model/` (options, findings,
results), `workspace/` (the package on disk), `source/` (source text and the
server's view of it), `lsp/` (the analysis server session), `conventions/`
and `project_config/` (what keeps declarations alive), `collect/`, `fetch/`
and `settle/` (the pipeline), `remove/`, `report/`, `cli/` and `util/`.
`lib/src/finder.dart` wires the stages, and its library doc maps the
directories; keep that map current when a directory is added or renamed. Put
new code in the directory of its stage, never at the `lib/src/` root. Tests
mirror the layout under `test/`, with the end-to-end runs that drive `Ciach`
against `example/` in `test/finder/`.

Name a file after what it holds, one concern per file: one report format per
`report/<format>_report.dart`, the `with`/`implements` clause rule in
`settle/clause_only_types.dart`. Lower layers never import higher ones; a doc
link to a higher-layer name goes in backticks instead of an import.

# File size

Keep a file under about 500 lines. Split by responsibility, not by line count:
pull out a concern with its own state and name (the cross-library recovery,
the transitive sweep), move a helper onto the type that owns its data
(`DeadSpans.referrersAmong`), or give each variant its own file (the report
formats). When a split moves code, keep the upstream names and wording, and
leave a file that only moves with its existing content and header as it is.

# AI-Provenance headers

A file created in a session names the model that created it, whatever model
wrote the code it was split out of. A file that only moved or was renamed
keeps the header it had. Never copy a model id from another file.

# Before pushing

Use the newest patch of the Dart SDK line CI installs (`sdk: 'x.y'` in
`.github/workflows/test.yml`): an older patch can format differently. Then
run what CI runs. In the root, where `dart pub get` also resolves `example/`:
`dart analyze`, `dart format --set-exit-if-changed .` and `dart test`. In
`tool/ciach_lints/`: `dart pub get` and `dart test`. In `website/`, a Dart
package of its own with its own workflow: `dart pub get`,
`dart analyze --fatal-infos`, `dart format --set-exit-if-changed .` and
`dart test`, which renders the committed assets and compares them.

When the base branch moves, merge it in; never rebase a pushed branch. A hunk
that lands in a file a split emptied belongs in the file its code moved to:
port it there, then drop the upstream copy.
