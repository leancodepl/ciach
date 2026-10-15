# Writing

These rules apply to every sentence you write: doc comments, code comments,
test names, messages, `--help`, README.md, the website, the changelog, pull
request descriptions and review replies.

- Write full sentences that read right the first time. Keep "that", "which",
  articles and verbs: "the field statement that the symbols belong to", not
  "the statement the symbols belong to". Don't stack nouns ("analysis server
  plugin entry point"); use a verb ("called by the analysis server"). Short
  means fewer ideas, not fewer words per idea.
- Say things literally. Avoid stilted or figurative turns such as "X, less the
  Y", "gives way to", "is dead with", "reads as unused" or "knows a CI runner
  from a terminal".
- Make every reference point at something the reader can see. Write "too",
  "also", "both", "there", "these prefixes" or "the change" only when the same
  sentence names what they refer to. In a doc comment, name the parameters you
  mean: `[rootPath]`.
- Use words the reader already knows: the Dart spec's terms ("directive",
  "mixin application class") rather than analysis server enum names
  (`CLASS_TYPE_ALIAS`), and no terms you coined, such as "walk", "cut" or
  "trivia".
- State what always happens as a fact. Write "may" only for what really
  varies.
- Check what a sentence says ciach does ("are generated" reads as if ciach
  generated the files), and whether it has a second reading ("on the line before
  a declaration or after it").
- Don't pad. Leave out the history of which version added what, version notes
  that every supported setup meets (ciach needs Dart 3.10, which means Flutter
  3.38), explanations of Dart basics, and a word repeated a few words later.
- Use US spelling, and a neutral tone in docs: "the marker says that they are
  kept on purpose", not "you said so".
- When a reviewer flags one sentence, reread all the prose the pull request
  adds, and every copy of it, before you reply. Reread a rewrite as critically
  as the first version; rewrites have been flagged again.

# CHANGELOG.md

End every entry with a link to its pull request, never to an issue:
`([#N](https://github.com/leancodepl/ciach/pull/N))`. Before committing an
entry, run `dart run tool/check_changelog.dart --pr N`; CI runs the same check.

Write an entry for the people who use ciach. In one to three short, plain
sentences, say what was added, fixed or changed, as they will see it. For a
fix, say what went wrong before. Leave out how it was implemented: no class or
method names, internal terms or reasoning about the code.

Every pull request that changes what users see adds its entry under
`## Unreleased`, without being asked. Write one entry per change and name every
effect that users will notice; when a change has several parts, list them.
Start with the change itself, such as "Fix …", "Stop reporting …" or
"`--remove` now …", not with a definition ("Test calls are not declarations")
or a list of edge cases. A fix for a bug that the same pull request introduced
gets no entry. A breaking entry says what changed and links MIGRATION.md, which
alone holds the steps to adapt. Leave the entries of other pull requests alone.
When you shorten an entry, cut the explanation and keep every change.

# User docs

README.md, the docs page in `website/lib/pages/docs_page.dart`, the `--help`
text and MIGRATION.md describe what ciach does and how to use it, in short,
easy-to-follow sentences, not how it works inside.

- Describe an option the same way in README.md, on the website and in
  `lib/src/cli/args.dart`, and change all three together. The example configs
  in README.md and `lib/src/cli/usage.dart` show the same options.
- Take sample output from a real run on `example/`, and paste it as it is.
  Never compose it by hand.
- README.md covers the current version. Removed options and upgrade steps go in
  MIGRATION.md. Notes for library users go in the doc comment of the API they
  concern, and notes on which tool versions a parser supports go next to that
  parser. Leave out caveats that a lint already enforces.
- Prefer a sentence and a short list to a long paragraph or a dense table.
- When a change makes a statement in the docs untrue, fix the statement, and
  check every list of defaults or effects against the code.

# CLI output

- Say what happened and, if needed, what to do. Leave out the reasoning, and
  don't add a line that repeats what the output already shows.
- Put option names, config keys, values and code in backticks, so that the
  reader sees where each one starts and ends.
- List file locations one per line under a lead-in line, never joined with
  commas, and check the result with long, real paths.
- Build a line from a list of the parts that apply, joined with one separator,
  as the finding rows in `report/text_report.dart` do. Don't give each optional
  part its own leading spaces and a `''` fallback.
- Write counts with `plural(n, 'file', 'files')` from `util/plural.dart`, never
  "(s)".
- An option's help text says in one or two sentences what the option is for and
  what its default is. Its placeholder looks like the others
  (`--kinds=<kind,kind>`), and a repeatable option is described in the
  singular.
- Report a problem once, on the type that owns it, with a short hint that
  doesn't list the type's members.
- A lint's message and fix title say what the fix will do in this case, and
  show the replacement.

# Code comments

A doc comment says what the member does or returns, starting with a verb
("Returns …"), in one or two lines like those of its neighbors. Don't add doc
comments that its siblings lack or that repeat the name, and don't describe the
internal steps or why a caller needs the member. When a name confuses a reader,
rename it instead of lengthening its comment.

A comment says what the code can't: why a condition needs all rather than any,
which part of a category a function handles and why, whether paths are
absolute, how the duplicates that a dedupe removes arise, or which known
algorithm a loop implements. It doesn't explain Dart, argue against an
alternative nobody proposed, or narrate. A file whose purpose isn't obvious
gets a library doc comment, and a long inline fixture gets a comment on each
part; an explanation that lives only in a review reply is lost. Give concrete
values: "the server names it `extension on String`", not "the server's
placeholder name".

When a change makes a comment wrong, fix the comment in the same commit. Keep
the borders of a Markdown table in a doc comment aligned, and leave a TODO at a
workaround for a bug that a later pull request will fix.

# Names

Name a thing after what it holds or returns, in plain words: `libraryFiles`,
`paths`, `EntryPoint.fromConfig`. Avoid metaphors (`span`, `Spelling`),
data-structure words that don't apply (`tree` for a cache), vague words
(`checked`, `site`, `hit`, `target`) and compiler jargon (`Trivia`). Read the
name as a word on its own (`uncut` became `lacksCut`), make sure it can't be
read as its opposite (`dead` for containers not yet proven live), and avoid
stutter (`button-button`).

A name claims no more than the code does, and it doesn't list every case
either: `_directiveEnd`, for a function that skips only some directives, and
`_libraryImportOrPartOfEnd` were both rejected. Name a predicate after the
property that the caller tests (`isDeclaration`), not after the case that
prompted it (`isUnitTest`). Keep an enum's values on one axis; an enum that is
only ever compared with `==` probably mixes two facts.

When names confuse a reviewer, describe what the code does in one sentence,
take one small vocabulary from that sentence, and rename every identifier,
comment and test that uses the old words. Don't add one qualifier per review
round ("maybe-dead", "pending", "waiting"). Before pushing a rename, check it
against the reviewer's complaint.

# String literals

Write a string as one literal. Use a `'''` multi-line string for text with
interior newlines (expected output, fixtures); the `prefer_multiline_string`
rule in `tool/ciach_lints` flags a single-line literal with two or more
interior `\n` escapes and offers a quick-fix that rewrites it. Split a string
into adjacent literals only when the joined line would run past 120 columns,
and never leave a short fragment in a literal of its own. Test and group
descriptions follow the same rule, even when `dart format` then spreads the
call over more lines. Never wrap with `+`. Option help texts in
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

To use a nullable value in a block or a collection literal, unwrap it with
`if (x case final v?)`, never with `x!` or by looping over `x ?? const []`. Put
the fallback of a null-aware chain last, as in `xs?.map(f) ?? const []`, and
use `?.` rather than an explicit null check.

# Patterns

- Branch on several values with one `switch ((rule, container))` over record
  patterns, not with `if` conditions that repeat the same null checks.
- Put type tests, null checks and field values in the pattern, not in a `when`
  guard: `SemanticToken(isKeyword: true, :final text)`,
  `PropertyAccess(:final target?)`, `parent: final SwitchExpression switch_`.
  Capture a field under its own name, and use the promoted variable rather than
  binding a second name for it.
- Merge arms with the same body with `||`, and merge nested `if`s into one
  if-case with a `when` guard.
- A function that picks a result by the shape of a value is a switch
  expression, without if/return chains or nested conditional expressions. Read
  JSON and YAML with a switch over map patterns. Bind and test in one step:
  `if (files.length + variants.length case final count && > 0)`.

# Idioms

- Return a result; never fill a list that the caller passes in. A function that
  only builds a collection is `sync*`, or an expression body with a collection
  literal that uses `for`, `if` and `?key:`.
- Keep an `Iterable` lazy when it is read once or in part, and use a `Set` when
  duplicates mean nothing.
- Prefer `for (final (i, x) in xs.indexed)` to an index loop, `whereNot(f)` and
  `none(f)` to negations, collection methods (`where`, `firstWhereOrNull`) to
  loops with early returns, tear-offs to lambdas that only forward, `min` and
  `max` to hand-written ternaries, `map[key] ??= value` to
  `putIfAbsent(key, () => value)`, and `package:collection` equalities to
  comparison loops.
- A record that crosses a function boundary has named fields. Model structured
  data as a record or class, never as a preformatted string whose format a
  comment describes, or as parallel lists indexed by an int. Group related
  constants in an enum.
- In a function type, name every parameter or none.
- Declare a value inside the `try` that produces it, as `final`. Catch the
  exception that the call throws (`LspException`, `FileSystemException`). A
  catch-all `on Object` turns a crash into quietly worse results, so use one
  only for best-effort cleanup, with a comment.
- Inline a local or a helper that is used once. Give a regex named groups, and
  return names and offsets rather than a `RegExpMatch`.
- In `website/`, keep a component's styles next to it as Jaspr `@css`, make
  repeated pieces (buttons, cards, pills) components, and write `.only()`,
  `.symmetric()` or `.all()` rather than `fromLTRB()`.

# Design

- Before writing a helper, look for one: in `lib/src/util/` (`CachedMap`,
  `reachability.dart`, `plural.dart`, `extensions.dart`), in
  `package:collection`, `package:path`, `Uri`, `package:xml` and
  `package_config`, in a library's own constants (pro_lsp's `RequestMethod`),
  and in LeanCode's packages (`jaspr_class_scope`). Search sorted data with the
  existing binary searches, `lastStartingAtOrBefore` in `source/symbols.dart`
  and `firstIndexAtOrAfter` in `lsp/semantic_tokens.dart`, instead of scanning
  it or writing another one.
- Read Dart source through the analysis server (outline, selection ranges,
  semantic tokens, hover), not with regexes, text matching or a hand-written
  tokenizer: `required` is also a valid parameter name. A regex over Dart
  source needs a comment that says why. Check what is already cached before
  you call a server request too costly.
- Keep each default, rule and fact in one place, and let everything else read
  it. When a type takes over a normalization or a check, delete the old copy,
  and put a check that guards correctness in the library API, not only in the
  CLI. A request to unify two paths ends with one path, not two lists.
- Don't write code without a reason: a guard for a case that can't happen (a
  test must fail without each condition), a shortcut nobody measured, a stored
  copy of a value that you can compute, a field that passes state to another
  method behind its back, a value built twice, a one-field JSON object, an
  unused style or variant, or a factory left over from a refactor.
- Don't add what nobody asked for: an escape-hatch flag, a deprecated alias, a
  second spelling of an input, the mirror image of a quick fix. Ask first.
  Reject a wrong input with an error that names the right form.
- Prefer a general rule to one package's or framework's special case, and say
  in the pull request why a special case stays. Report an idiom that has a
  cleaner replacement, with a hint, instead of skipping it, and report what
  ciach can't remove (obsolete l10n keys) as not removable instead of hiding
  it.
- Don't let a default that deletes code rest on a guess such as
  `publish_to: none`; prefer explicit config with the safe default.
- Never leave code that doesn't build, or a comment that names deleted code.
  When a removal can't be clean, block it and say what the user should change.
  When the complete change is possible, make it in the same pull request and
  list the cases that block it, instead of shipping a report-only half step.
  Don't exclude a hard case as a shortcut: check what the exclusion does to the
  rest, and whether it undoes the point of the pull request.
- Every code path honors an option's documented contract: `--exclude` also
  applies to files that are opened only to resolve references, and findings
  carry the kind names that `--kinds` filters on.
- Results must not depend on input order. Break ties explicitly, collect every
  match rather than the first one that the server lists, and make sure that a
  repeat-until-stable loop settles.
- Config takes YAML lists and maps with named fields, not a small grammar inside
  a string (`glob:name`), and keeps data such as declaration names in values,
  not keys.
- Don't run `git` or other programs when the environment or the file system can
  answer, and write tooling in Dart, not Node.
- When a lint fires, check whether its concern applies here; JavaScript number
  precision doesn't. If it doesn't, add one `// ignore:` with the reason.
- When a LeanCode library forces the same workaround at every call site, change
  the library.

# Tests

- A test name states the scenario and the result in full words, with code in
  backticks.
- Before asking for review, cover the boundaries and every equivalent form: the
  first, last and only element, all of them, mixed dead and live parts, an
  enhanced enum, generic classes, methods and extensions, positional and named
  parameters, each syntax that can name a declaration (`is`, `is!`, `.new()`,
  `.named()`, `Class.new`), and the neighboring kinds that must not change. A
  rule that matches by name gets a test with an unrelated declaration of the
  same name. Compile each negative case to check that it really differs.
- Every check that you run to answer a reviewer becomes a committed test.
- Compare records, not strings that encode several fields, and call the code
  under test once per test.
- Put each case under the test that names it, and a mechanism's fixtures in one
  `example/lib/scenarios/<mechanism>.dart`. Comment an edit to an unrelated
  fixture.
- Test your own code, not the behavior of a library that it calls.
- Don't pin output that you know is invalid Dart without saying so in the pull
  request.
- Before refactoring code that prints output, pin the output with a test.
  Check hashing and bit operations against a published value.

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

A general-purpose helper goes in `lib/src/util/`, not in a private extension in
the first file that needs it. Keep `bin/ciach.dart` thin: what it calls lives
in `lib/src/cli/`. Handle a stage's failures inside that stage, not in the code
that runs the stages.

# File size

Keep a file under about 500 lines. Split by responsibility, not by line count:
pull out a concern with its own state and name (the cross-library recovery,
the transitive sweep), move a helper onto the type that owns its data
(`DeadSpans.referrersAmong`), or give each variant its own file (the report
formats). When a split moves code, keep the upstream names and wording, and
leave a file that only moves with its existing content and header as it is.

The limit holds for test files too, with shared helpers in `test/support/`.
Split a file in the pull request that pushes it past the limit, instead of
promising a follow-up. Split a function that has several loops or phases into
named steps.

# AI-Provenance headers

A file created in a session names the model that created it, whatever model
wrote the code it was split out of. A file that only moved or was renamed
keeps the header it had. Never copy a model id from another file.

# Check before you claim

Check a claim before you write it: how the code behaves, what a library, the
SDK or the analysis server does, what a change costs, what the repository has
(secrets, variables), how other projects use a feature, or that something
doesn't exist. Run the case, read the code, measure, or search pub properly.
When something is a guess, say so. This applies to review replies, pull request
descriptions, docs and this file.

- A reply that says "Done in `abc1234`" names a commit on the pull request's
  branch.
- When asked to simplify something, try it before saying that it can't be
  simpler.
- Don't justify leaving a case out with a limit you haven't checked ("can't be
  told apart").
- Describe a bug by its repro and the wrong output you saw, not by the harm
  that it might do.
- When a claim turns out wrong, correct it everywhere you posted it, and update
  a thread when a later commit reverses what you said there.
- In docs, point at the source of truth (`sdk:` in the workflow) rather than
  copying a value that will go stale.

# Review comments

- Read all of it: review bodies, conversation comments and every thread, not
  only the inline comments. Reread the whole thread before you say that a fix
  is done.
- A short remark on a line that the pull request made wrong ("this PR updates
  this behavior") asks you to fix that line. When a reviewer asks only for an
  answer, answer and don't commit. When you can't tell what a comment wants (an
  emoji, "nicer before"), ask, and never undo something that the reviewer asked
  for earlier.
- Do all that a comment asks: both halves of a two-part request, and an edit of
  the description when asked, not an offer to make one. Do obvious companion
  work, such as the changelog entry or a CI job for a new SDK floor, instead of
  offering it. When a reviewer has sketched a shape, build that shape or say
  why not.
- When a reviewer flags a pattern, fix every instance in the pull request. When
  they suggest a change to one line, don't copy it onto code that didn't have
  the problem.
- Answer the question that was asked first, in a sentence or two, without an
  essay. If the same code needs explaining twice, rename it.
- If a fix meets only part of the concern, say which part.
- Don't cite this file to defend a choice that the reviewer rejected: a rule
  that allows something doesn't require it.
- Post each reply once and in the right thread, and don't offer to wait for
  input on a change that you have already pushed.
- When the same correction comes up a second time, propose a lint in
  `tool/ciach_lints`, the way `prefer_let` and `prefer_multiline_string` came
  about.

# Pull requests

- One concern per pull request. A behavior change that comes up while reviewing
  a restructuring goes in its own stacked pull request, and so do drive-by
  changes. After splitting a pull request in two, remove what only the other
  half needed.
- The description says what the pull request does, in proportion to its size,
  without lists of private names, superlatives or guesses about other pull
  requests. Keep it true when review changes the behavior, and say what you
  removed and why.
- Write test notes that a reader can check: "Without the `'variable'` line in
  `cross_library_refs.dart`, the new case fails on Dart 3.13.4; all tests pass
  with this pull request."
- End the description with one attribution footer, not two.
- Do the steps that this file asks for, such as a provenance header or a
  changelog entry, instead of listing them as to-dos.

# GitHub workflows

Pin each action to a commit SHA of its current major version, with the version
in a comment: `actions/checkout@<sha> # v7.0.0`. A workflow holds only the
steps that every run needs; one-time setup, such as assigning a domain, is done
by hand. Indent a `run:` script as a block. Mark committed generated files as
`linguist-generated` in `.gitattributes`.

# Before pushing

Use the newest patch of the Dart SDK line CI installs (`sdk: 'x.y'` in
`.github/workflows/test.yml`): an older patch can format differently. Then
run what CI runs. In the root, where `dart pub get` also resolves `example/`:
`dart analyze`, `dart format --set-exit-if-changed .` and `dart test`. In
`tool/ciach_lints/`: `dart pub get` and `dart test`. In `website/`, a Dart
package of its own with its own workflow: `dart pub get`,
`dart analyze --fatal-infos`, `dart format --set-exit-if-changed .` and
`dart test`, which renders the committed assets and compares them.

When the base branch moves, merge it in; never rebase, amend or force-push a
pushed branch, also when asked to update it with `main`. A hunk that lands in a
file a split emptied belongs in the file its code moved to: port it there, then
drop the upstream copy. After resolving a conflict in prose, reread the section
against both sides, so that no heading or paragraph is lost.
