# Writing

The rules in this section apply to every sentence you write: doc comments, code
comments, test names, messages, `--help`, README.md, the website, the
changelog, pull request descriptions and review replies.

- Write full sentences that read right the first time. Keep "that" and "which"
  where they make a sentence easier to read, and keep articles and verbs: "the
  statement that the symbols belong to", not "the statement the symbols belong
  to". Don't stack nouns ("analysis server plugin entry point"); use a verb
  ("called by the analysis server"). Short means fewer ideas, not fewer words
  per idea.
- Say things literally. Avoid stilted or figurative phrases such as "X, less
  the Y", "gives way to", "is dead with", "reads as unused" or "knows a CI
  runner from a terminal".
- Make every reference clear. Write "too", "also", "both", "there", "these
  prefixes" or "the change" only when the same sentence names what they refer
  to. Don't leave out a predicate ("each member is a finding, but they aren't")
  or use a pronoun that could mean two things. In a doc comment, name the
  parameters you mean: `[rootPath]`.
- Use the Dart spec's terms ("mixin application class"), not analysis server
  enum names (`CLASS_TYPE_ALIAS`). Don't use a term that you coined, such as
  "walk" for a recursive pass. In user docs, say what happens to the user's
  code: "the `import`s of it are removed", not "the directives that named it
  are dropped".
- State what always happens as a fact. Write "may" only for what really
  varies.
- Check what a sentence suggests that ciach does ("are generated" suggests that
  ciach generated the files), and whether it can be read a second way ("on the
  line before a declaration or after it").
- Don't pad. Leave out the history of which version added what, and notes about
  versions that every supported setup already has; the `sdk:` constraint in
  `pubspec.yaml` says what is supported.
- Don't repeat a word a few words after you used it ("Detect CI. In CI, …").
- Use US spelling, and a neutral tone in docs: "the marker says that they are
  kept on purpose", not "you said so".
- When a change makes any text untrue, whether a comment, the docs, the help
  text or the pull request description, fix that text in the same change.
- When a reviewer flags one sentence, reread all the prose that the pull
  request adds, including the copies of that sentence in other files, before
  you reply. Reread your rewrite as critically as the sentence it replaces.

# CHANGELOG.md

End every entry with a link to its pull request, never to an issue:
`([#N](https://github.com/leancodepl/ciach/pull/N))`. Before committing an
entry, run `dart run tool/check_changelog.dart --pr N`; CI runs the same check.

Write an entry for the people who use ciach. In one to three short, plain
sentences, say what was added, fixed or changed, as they will see it, and keep
it about as long as the entries around it, also after a later commit adds an
effect to it. For a fix, say what went wrong before. Leave out how it was
implemented: no class or method names, internal terms or reasoning about the
code.

Every pull request that changes what users see adds its entry under
`## Unreleased`, without being asked. Write one entry per change and name every
effect that users will notice; when a change has several parts, list them.
Start with the change itself, such as "Fix …", "Stop reporting …" or
"`--remove` now …", not with a definition ("Test calls are not declarations")
or a list of edge cases. A fix for a bug that the same pull request introduced
gets no entry. An entry for a breaking change says what changed and links
MIGRATION.md, which alone holds the steps to adapt. Leave the entries of other
pull requests alone. When you shorten an entry, cut the explanation and keep
every change.

# User docs

README.md, the docs page in `website/content/docs.md`, the `--help`
text and MIGRATION.md describe what ciach does and how to use it, in short,
easy-to-follow sentences, not how it works inside.

- List every option in README.md. Describe an option the same way wherever it
  appears, in README.md, on the website and in `lib/src/cli/args.dart`, and
  change every copy together. When you add an option that most setups need,
  add it to the example configs in README.md and `lib/src/cli/usage.dart`.
- Take sample output from a real run on `example/`, and paste it as it is.
  Never compose it by hand.
- README.md is the short path through ciach: install, run, read the report,
  the options. The docs page holds every detail, written in Markdown with one
  `##` section per file under `website/content/_partials/docs/`, which
  `website/content/docs.md` includes in order, and each README section links
  to its section there by the id that the heading generates.
  Put a new detail on the docs page, and in README.md only when every user
  needs it.
- README.md starts with a `## Contents` list of its `##` and `###` headings.
  `test/readme_toc_test.dart` checks it against the file, so run `dart test`
  after changing a heading.
- README.md covers the current version. Removed options and upgrade steps go in
  MIGRATION.md. Notes for library users go in the doc comment of the API that
  they concern, and notes on which tool versions a parser supports go next to
  that parser. Leave out warnings about conventions that a lint already
  enforces.
- Prefer a sentence and a short list to a long paragraph or a dense table, and
  don't add an example that repeats the options table. Keep aligned blocks
  aligned, such as the trailing `#` comments of a code sample.
- Check every list of defaults or effects against the code. When the docs
  describe a failure, name every effect that a user can see and where it shows
  up in the output.

# CLI output

- Say what happened and, if needed, what to do. Leave out the reasoning, and
  don't add a line that repeats what the output already shows.
- Put option names, config keys, values and code in backticks, so that the
  reader sees where each one starts and ends.
- List file locations one per line under a lead-in line, never joined with
  commas, and check the result with long, real paths.
- Build a line from a list of the parts that apply, joined with one separator,
  as the finding rows do (`columns.join('  ')` in
  `lib/src/report/text_report.dart`). Don't give each optional part its own
  leading spaces and a `''` fallback.
- Write counts with `plural(n, 'file', 'files')` from
  `lib/src/util/plural.dart`, never "(s)".
- An option's help text says in one or two sentences what the option is for and
  what its default is. Its placeholder looks like the other options'
  placeholders (`--kinds=<kind,kind>`), and a repeatable option is described in
  the singular.
- Report a problem once, on the class, mixin, extension or enum that has it,
  with a short hint that doesn't list its members.
- A lint's message and fix title say what the fix will do to the flagged code,
  and show the replacement. The fix produces the shortest idiomatic form:
  `s?.length` before `s?.let(…)`. It leaves nothing for the lint to flag, so
  it makes every rewrite that running it again would make, and its tests
  check that the fixed code compiles with no diagnostics.

# Code comments

A function's doc comment starts with what the function does or returns
("Returns …"), says what a parameter holds when that isn't obvious, and gives
an example when a term is abstract. Keep it about as short as the doc comments
of its neighbors. Leave the evidence for a claim, such as the SDK
code that you read or how many runs you checked, to the pull request and the
review reply. Don't add doc comments that the member's siblings lack or
that repeat the name, and don't describe the internal steps or why a caller
needs the member. When a name confuses a reader, rename it instead of
lengthening its comment.

A comment says what the code can't show: why a condition needs all rather than
any, which part of a category a function handles and why, whether paths are
absolute, how the duplicates that a dedupe removes arise, or which known
algorithm a loop implements. Define a domain term, such as "variant", where it
first appears, and give a loop whose result isn't obvious a one-line example.
Give concrete values: "the server names it `extension on String`", not "the
server's placeholder name". A comment doesn't explain Dart, such as why a
field has a declared type, repeat a rule from this file, argue against an
alternative that nobody proposed, or retell how the code came to be. Put a
comment at the code that it explains: a reason why a step is skipped goes
where the step runs, not next to the code before it.

A file whose purpose isn't obvious gets a library doc comment, and a long
inline fixture gets a comment on each part. When a reviewer asks you to explain
code, answer in the reply, and add a comment only when they ask for one.
Keep the borders of a Markdown table in a doc comment aligned, and leave a TODO
at a workaround for a bug that a later pull request will fix.

# Names

Name a thing after what it holds or returns, or a constructor after where its
input comes from, in plain words: `libraryFiles`, `paths`,
`EntryPoint.fromConfig`. Avoid metaphors (`span` for the files a directive can
choose between, `Spelling`), data-structure words that don't apply (`tree` for
a cache), vague words (`checked`, `site`, `hit`, `target`) and compiler jargon
(`Trivia`). Read the name as a word on its own (`uncut` became `lacksCut`),
make sure it can't be read as its opposite (`dead` for containers not yet
proven live), and avoid stutter (`button-button`). When two fields hold nearly
the same data, make the difference show in their names.

A name claims no more than the code does, and it doesn't list cases either.
`_directiveEnd` claimed every directive for a function that skips only some,
`_libraryImportOrPartOfEnd` listed every case, and the lint name
`prefer_none_and_where_not` listed two of the five methods that the lint
suggests; all three were rejected. Name a lint after what it flags,
`avoid_negated_iterable_predicates`, or after the form that its fix writes,
`prefer_let`. That form covers every rewrite of the fix: `prefer_indexed_loop`
was rejected because its fix also writes plain `for-in` loops.
Name a predicate after the property that the caller tests (`isDeclaration`),
not after the case that prompted it (`isUnitTest`). Make every value of an enum
answer the same question.

When names confuse a reviewer, describe what the code does in one sentence,
pick a few words from that sentence, and use them for every identifier, comment
and test that used the old words. Don't add one qualifier per review round
("maybe-dead", "pending", "waiting"). Before pushing a rename, check it against
the reviewer's complaint.

# String literals

Write a string as one literal. Use a `'''` multi-line string for text with
interior newlines (expected output, fixtures); the `prefer_multiline_string`
rule in `tool/ciach_lints` flags a single-line literal with two or more
interior `\n` escapes and offers a quick-fix that rewrites it. Adjacent
literals are for a line that would run past 120 columns:
`prefer_single_string_literal` flags and joins the others, test and group
descriptions included. Never leave a short fragment in a literal of its own,
and never wrap with `+`. Option help texts in `lib/src/cli/args.dart` are
plain sentences with no `\n`; the parser wraps them (`usageLineLength`).

# Dot shorthands

Use a dot shorthand wherever the context type lets you: `.new(path, c)`
rather than `DeclKey(path, c)`, `.plain` rather than `Style.plain`, including
inside lambdas whose return type the context already fixes. Never replace a
shorthand with the full type name. Annotation arguments are the exception:
`@Timeout(Duration(minutes: 5))` stays, since `package:test` parses it with
an evaluator of its own that knows no shorthands. Give a top-level or static
field a declared type when its initializer has a shorthand inside the
arguments of another one, such as `const .new(.publicMembers, …)`: Dart 3.10,
the SDK floor, can't resolve the inner shorthand while it infers the field's
type. leancode_lint's
`prefer_dot_shorthand` rule, enabled in `analysis_options.yaml`, enforces all
of this.

# Nullable chains

Use `x?.let(f)` from `lib/src/util/extensions.dart` rather than
`switch (x) { final v? => f(v), null => null }` or `x == null ? null : f(x)`,
and `x?.let(f) ?? d` rather than `x == null ? d : f(x)`, also for a value a
null check cannot promote: `a.b?.let(f) ?? d`, never `a.b == null ? d :
f(a.b!)`. Read as much as possible before the `let`, in the null-aware chain:
`x?.y.let(f)`, not `x?.let((it) => f(it.y))`.

To use a nullable value in a block or a collection literal, write
`if (x != null)` when the null check promotes `x`, as it does a local
variable, a parameter or a private final field. Otherwise, unwrap the value
with `if (a.x case final x?)`. `avoid_empty_collection_fallback` flags a loop,
a spread or a call on `x ?? const []`. Write `x!` only where the code already
guarantees the value. Put the fallback of a null-aware chain last, as in
`xs?.map(f) ?? const []`, and in an expression, use `?.` rather than an
explicit null check.

# Patterns

- Branch on several values with one switch over a record, such as
  `switch ((key, value))` in `lib/src/cli/removed_options.dart`, not with `if`
  conditions that repeat the same null checks.
- Put type tests, null checks and field values in the pattern, not in a `when`
  guard: `SemanticToken(isKeyword: true, :final text)`,
  `PropertyAccess(:final target?)`. `prefer_pattern_over_guard` flags a guard
  that makes such a test on a variable of its own pattern, and moves the test.
  Capture a field under its own name with the shorthand: `:final name?`, not
  `name: final name?`. Do so also when the pattern gives the field a type:
  `:final ExecutableFragment? declaredFragment`, not
  `declaredFragment: final ExecutableFragment? fragment`. Use the promoted
  variable rather than binding a second name for it.
- Use the simplest pattern that does the job:
  `if (symbol.children case final children? when …)` rather than an object
  pattern that destructures fields that are read once. A record, list or map
  pattern, and an object pattern of a non-nullable type, never match `null`,
  so they need no `?`: `case (:final range, :final code)`, not
  `case (:final range, :final code)?`.
- `merge_identical_switch_arms` joins neighboring arms that have the same body
  with `||`. Merge nested `if`s into one if-case with a `when` guard.
- A function that picks a result by the shape of a value is a switch
  expression, without if/return chains or nested conditional expressions. Read
  JSON and YAML with a switch over map patterns. Bind and test in one step,
  the binding first: `case final count && > 0`, and
  `case final path? && != unknownPackage` rather than
  `case (!= unknownPackage && final path)?`.

# Idioms

- Return a result; never fill a list that the caller passes in, or replace its
  elements. A function that only builds a collection is `sync*`, or an
  expression body with a collection literal that uses `for`, `if` and
  `?key:`. A plain filter is `where(f)`, with
  `.toSet()` or `.toList()` when needed, not a collection-for literal. Never
  turn a collection literal into an imperative loop unless asked; when a
  literal gets busy, give its predicate a named local.
- Keep an `Iterable` lazy when it is read once or in part, and use a `Set` when
  duplicates mean nothing.
- Prefer collection methods (`where`, `firstWhereOrNull`) to loops with early
  returns, tear-offs to lambdas that only forward, `min` and `max` to
  hand-written ternaries, and `package:collection` equalities to comparison
  loops. Write `map[key] ??= value` for a value that you already have, and
  memoize with `CachedMap`. `prefer_for_in_loop` replaces an index loop that
  reads `xs[i]` with `for (final x in xs)` or
  `for (final (i, x) in xs.indexed)`. `avoid_negated_iterable_predicates`
  replaces negations with `none(f)` and `whereNot(f)`, and
  `any((x) => !f(x))` with `!every(f)`.
- A type that has its own name and meaning, such as `QualifiedMember`, is a
  class, not a record typedef. A record that a function returns or yields has
  named fields. Never model data as a preformatted string whose format a
  comment describes, or as parallel lists indexed by an int.
- Pass typed values, such as a `ClassName`, through an API, and turn them into
  strings only where they are printed. Group related constants in an enum.
- In a function type, name every parameter or none.
- Order branches so that each one returns before any work that it doesn't
  need.
- Declare a value inside the `try` that produces it, as `final`. Catch the
  exception that the call throws (`LspRequestException`,
  `FileSystemException`). A catch-all `on Object` turns a crash into quietly
  worse results, so use one only to wrap and rethrow, to report a crash at the
  top of `main`, or for best-effort cleanup with a comment.
- Inline a local or a helper that is used once when its name adds nothing; keep
  one whose name says what a step does. Give a regex named groups, and return
  names and offsets rather than a `RegExpMatch`.
- Give an asynchronous step a named method instead of a closure that is called
  where it is written: `_pending[path] ??= _requestTokens(client, path)`, not
  `_pending[path] ??= () async { … }()`.
- In `website/`, keep a component's styles next to it as Jaspr `@css`, make
  repeated pieces (buttons, cards, pills) components, and write `.only()`,
  `.symmetric()` or `.all()` rather than `fromLTRB()`.
- In `website/`, set a CSS property through its typed `Styles` parameter
  whenever Jaspr has one, even when the parameter writes longhands or a whole
  border: `flex: growToFill`, not `raw: {'flex': '1'}`, and
  `border: hairline(accentColor)`, not `raw: {'border-color': …}`. When the
  parameter's type has no constructor for a value, pass `.expression()`, as in
  `maxWidth: const .expression('none')`. Keep `raw` for what Jaspr can't
  express, such as custom properties, gradients and `calc()` delays.

# Design

- Before writing a helper, look for one: in `lib/src/util/` (`CachedMap`,
  `reachability.dart`, `plural.dart`, `extensions.dart`), in
  `package:collection`, `package:path`, `Uri`, `package:xml` and
  `package_config`, in a library's own constants (pro_lsp's `RequestMethod`),
  and in LeanCode's packages (`jaspr_class_scope`). Search sorted data with the
  existing binary searches, `lastStartingAtOrBefore` in
  `lib/src/source/symbols.dart` and `firstIndexAtOrAfter` in
  `lib/src/lsp/semantic_tokens.dart`, instead of scanning it or writing another
  one. When the same expression or hand-written pattern appears a second time,
  give it a helper and replace every copy; share a function, not a regex
  constant.
- Read Dart source through the analysis server (outline, selection ranges,
  semantic tokens, hover), not with regexes, text matching or a hand-written
  tokenizer. Text matching mistakes a parameter named `required` for the
  keyword. A regex over Dart source needs a comment that says why. Check what is
  already cached before you call a server request too costly.
- Keep each default, rule and fact in one place, and let everything else read
  it. When a type takes over a normalization or a check, delete the old copy,
  or have both places call one shared predicate, such as `analysisRootContains`
  in `lib/src/util/paths.dart`. Put new matching logic on the type that
  owns the concept, such as `EntryPoint.matches`, not in side maps. A check
  that guards correctness belongs in the library API, not only in the CLI. A
  request to unify two code paths ends with one code path, not two lists.
- Don't write code without a reason: a guard for a case that can't happen (a
  test must fail without each condition), a shortcut that nobody measured
  (copying only the lists that change instead of all of them), a stored copy
  of a value that you can compute, a field that only carries state from one
  method to another, a value built twice, a one-field JSON object, an unused
  style or variant, or a factory left over from a refactor. Before wrapping a
  library call or its exception, check what the exception already carries.
- Don't put one caller's special case into a general function's result, such
  as a `null` placeholder in a list; handle it in that caller.
- When a later step adds to data that an earlier step combined, such as the
  references that conditional-import variants share, combine them again in
  that step, instead of keeping the step's input away from it.
- Don't add what nobody asked for: a flag that turns the new behavior off, a
  deprecated alias, a second accepted spelling of an input, or a second quick
  fix that goes the other way. Ask first. Reject a wrong input with an error
  that names the right form. Extend an existing helper, such as `runCli` in the
  tests, instead of adding a second way to do the same thing.
- Match a declaration that a library provides, such as `@pragma`, by its name
  and by the package that declares it, not by the name alone: a project can
  declare a `pragma` of its own.
- Prefer a general rule to one package's or framework's special case, and say
  in the pull request why a special case stays. Report an idiom that has a
  cleaner replacement, with a hint, instead of skipping it, and report what
  ciach can't remove (obsolete l10n keys) as not removable instead of hiding
  it.
- Don't let a default that deletes code rest on a guess such as
  `publish_to: none`; prefer explicit config with the safe default.
- Never leave the user's code unable to compile, or with a comment that names
  deleted code. When a removal can't be clean, block it and say what the user
  should change. When the complete change is possible, make it in the same pull
  request and list the cases that block it, instead of only reporting what a
  later pull request could remove.
- Don't leave a case out as a shortcut, and never because of a limit that you
  haven't checked ("can't be told apart"). Check what the exclusion does to the
  rest of the code, and whether it undoes the point of the pull request. This
  covers the cases that the change sets out to handle; whether to handle a new
  kind of case is the reviewer's decision, as "Deciding what to build" says.
- Findings carry the kind names that `--kinds` filters on.
- Results must not depend on input order. Break ties explicitly, collect every
  match rather than the first one that the server lists, and make sure that a
  repeat-until-stable loop settles.
- Config takes YAML lists and maps with named fields, not a small grammar inside
  a string (`glob:name`), and keeps data such as declaration names in values,
  not keys.
- Don't run `git` or other programs when the environment or the file system can
  answer, and write tooling in Dart, not Node.
- When a lint fires, check whether the problem that it guards against can
  happen in ciach; JavaScript number precision can't, because ciach runs on the
  Dart VM. If it can't, add one `// ignore:` with the reason.
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
- One test pins each default; other tests and group names don't restate it.
- Put each case under the test that names it. Keep a mechanism's fixtures
  together under `example/lib/scenarios/`, named after the mechanism, so that
  `example/` covers every kind that ciach reports. When a change forces an edit
  to an unrelated fixture, add a comment there that says why.
- Test your own code, not the behavior of a library that it calls.
- Test a function by calling it and checking its result, in the test file
  named after its library: `promotion_test.dart` calls `isPromotable`, not the
  fix that uses it. Leave its callers' tests to what the callers add.
- Don't pin output that you know is invalid Dart without saying so in the pull
  request.
- Before refactoring code that prints output, pin the output with a test.
- Check hashing and bit operations against a published value.

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
`settle/clause_only_types.dart`. A new helper goes in a file whose name covers
it, also when a similar helper already sits in a file about something else:
`positionIn` doesn't belong in `comment_stripping.dart` just because
`lineStartsOf` was there. A lower layer doesn't import a higher one: a
doc link to a higher-layer name goes in backticks instead of an import. Some
existing imports break this, such as `conventions/` importing
`collect/candidates.dart`; don't add more.

A general-purpose helper goes in `lib/src/util/`, not in a private extension in
the first file that needs it. Don't let `bin/ciach.dart` grow: new code that it
calls goes in `lib/src/cli/`. Handle a stage's failures inside that stage, not
in the code that runs the stages. Mark committed generated files as
`linguist-generated` in `.gitattributes`.

Every package in the repository depends on the same `leancode_lint` version and
includes the root `analysis_options.yaml`, so that all of them run the same
lint rules and plugins; `website/` adds `jaspr_lints`. A package turns a rule
off only in its own `analysis_options.yaml`, with a comment that says why.

# File size

Keep a file under about 500 lines. Split by responsibility, not by line count:
pull out a concern with its own state and name (the cross-library recovery,
the transitive sweep), move a helper onto the type that owns its data
(`DeadSpans.referrersAmong`), or give each variant its own file (the report
formats). When the subclasses of a sealed class are about 40 lines or longer
each, give each one a `part` file of the sealed class's library, as the
entry-point rules in `conventions/` do. Keep shorter subclasses next to the
sealed class, as `_Char` in `prefer_single_string_literal.dart` and the two
fixes in `version_matches_pubspec.dart` are. When a split moves
code, keep the upstream names and wording, and leave a file that only moves
with its existing content and header as it is.

Test files have the same limit, with shared helpers in `test/support/`. Split
a file in the pull request that pushes it past the limit, instead of promising
a follow-up. Split a function that has several loops or phases into named
steps.

# AI-Provenance headers

A file created in a session names the model that created it, whatever model
wrote the code it was split out of. A file that only moved or was renamed
keeps the header it had. Never copy a model id from another file.

# Check before you claim

Check a claim before you write it: how the code behaves, what a library, the
SDK or the analysis server does, what a change costs, what the repository has
(secrets, variables), how other projects use a feature, or that something
doesn't exist. Run the case, read the code, measure, or search pub properly.
When something is a guess, say so. These checks apply to review replies, pull
request descriptions, docs and this file.

- When asked to simplify something, try it before saying that it can't be
  simpler.
- Describe a bug by the steps that reproduce it and the wrong output that you
  saw, not by the harm that it might do.
- In docs, point at where a value is set rather than copying it, as "Before
  pushing" points at the workflow's `sdk:` key.

# Deciding what to build

A comment is either a request or a question. Build what a request asks for;
answer a question, and build nothing until the reviewer says yes.

- A request says what to do: "rename this", "use `whereNot` here", a
  suggestion block, or a short remark on a line that the pull request made
  wrong ("this PR updates this behavior"), which asks you to fix that line.
- A question asks for your view: "Would it be possible to …?", "Can't these be
  …?", "Aren't both valid?", an idea such as "We could also …", a 🤔, or a
  proposal with a doubt in it, such as "Maybe `prefer_simpler_iterators`?".
  Answer it and stop there. When you can't tell which kind a comment is (an
  emoji, "nicer before"), ask.
- To answer "Would it be possible …?", say whether it is possible and what it
  would cost: the code and tests that it adds, the new ways it could go wrong,
  and how many places it would change in this repository, which you count by
  running it or searching. Then recommend for or against. For example,
  supporting switch arms that other arms separate would have doubled
  `merge_identical_switch_arms`, could have sent a value to a different body,
  and flagged nothing in ciach, so it wasn't worth building.
- Weigh the value of every addition against its cost before you build it,
  also one that you thought of yourself. When it finds nothing in this
  repository or in `example/`, or when it adds more code than the problem
  warrants, say so instead of building it.
- A lint's fix must never change what the code does. When a new case would
  need a proof that a rewrite keeps the behavior, such as the order in which
  switch arms match, keep to the cases that are safe without the proof, and ask
  before building it.
- When a reviewer's proposal is tentative and you would choose something else,
  such as another name, propose your choice in the reply and wait for an
  answer before you push it.
- When an answer to a comment would make the pull request much bigger than the
  comment suggests, such as a new file, a file that doubles or more tests than
  the pull request had, stop and ask, with the numbers.
- The rules that say to do all that a comment asks, to do the companion work
  and not to leave a case out apply to requests. They never turn a question
  into a request.

# Review comments

- Read the whole review: review bodies, conversation comments and every
  thread, not only the inline comments. Reread the whole thread before you say
  that a fix is done.
- Never undo something that the reviewer asked for earlier.
- Do all that a comment asks: both halves of a two-part request, and an edit of
  the description when asked, not an offer to make one. Do obvious companion
  work, such as a CI job for a new SDK floor, instead of offering it. When a
  reviewer proposes a concrete shape, such as a config format, build that one,
  or say why not and propose yours before building it.
- When a reviewer flags a pattern, fix every instance in the pull request, and
  name the places in existing code that have the same problem. When they
  suggest a change to one line, don't copy it onto code that didn't have the
  problem.
- First answer the question that the reviewer asked, in a sentence or two,
  without an essay. When asked whether a tool or package exists, search
  properly and recommend one, rather than handing back a list of options.
- If a fix meets only part of the concern, say which part.
- A reply that says "Done in `abc1234`" names a commit on the pull request's
  branch. When a claim turns out wrong, correct it everywhere you posted it,
  and update a thread when a later commit reverses what you said there.
- Don't cite this file to defend a choice that the reviewer rejected: a rule
  that allows something doesn't require it.
- Post each reply once and in the right thread, and don't offer to wait for
  input on a change that you have already pushed.

# Keeping this file current

When a review comment on a pull request that you are writing corrects
something that a general rule could have prevented, add that rule here in the
same pull request, or sharpen the rule that should have caught it. On a pull
request that you didn't open, suggest the rule instead of pushing it.

- Write the rule one step more general than the comment: a rule against
  sentences that drop "that", not a fix for the one sentence. Keep a short
  example from the comment when it makes the rule clearer.
- Put the rule in the section that it belongs to, and follow the Writing
  rules. When a rule here already covers the case, sharpen it instead of adding
  a second one.
- When a reviewer asks for something that a rule here forbids, change the rule
  to match what they asked for.
- Leave out what concerns only one line of code, and questions that the
  reviewer only wanted answered.
- In your reply to the comment, say which rule you added or changed.
- Prefer a lint to a rule. When you add or sharpen a rule that a program could
  check, or a reviewer corrects code that a lint could have flagged, look for
  an existing lint in the Dart linter or `leancode_lint` and turn it on.
  Otherwise suggest a lint for `tool/ciach_lints` in your reply or in the pull
  request description, with the code that it would flag and how a quick fix
  would rewrite it. Once a lint enforces a rule, cut the rule here down to a
  pointer to the lint. `prefer_multiline_string` and `prefer_let` started as
  rules in this file.

# Pull requests

- Keep a pull request to one concern: unrelated features go in their own pull
  requests. A small fix to code that the pull request already touches belongs
  in it; size it before you propose a follow-up. After splitting a pull request
  in two, remove what only the other half needed.
- The description says what the pull request does, in proportion to its size,
  without lists of private names, superlatives or guesses about other pull
  requests. Say what you removed and why. When you write something that a
  package might already provide, say which packages you looked at and why they
  don't fit.
- Write test notes that a reader can check: "Without the `'variable'` line in
  `cross_library_refs.dart`, the new case fails on Dart 3.13.4; all tests pass
  with this pull request."
- End the description with one attribution footer, not two.
- Do the steps that this file asks for, such as a provenance header, instead of
  listing them as to-dos.
- When the pull request that yours is stacked on merges, retarget yours, and
  check that CI ran on its new head.

# GitHub workflows

Reference each action by the full release tag of its current major version,
such as `actions/checkout@v7.0.0` rather than `@v7`, and run `gh actions-lock`
after you change a `uses:` line. The command pins every action, including the
actions that a composite action uses, to a commit in
`.github/workflows/actions.lock`, and the `lockfile` workflow fails when that
file is out of date. A workflow holds only the steps that every run needs;
one-time setup, such as assigning a domain, is done by hand. Indent a
multi-line `run: |` script consistently.

# Before pushing

Use the newest patch of the Dart SDK line CI installs (`sdk: 'x.y'` in
`.github/workflows/test.yml`): an older patch can format differently. Then
run what CI runs. In the root, where `dart pub get` also resolves `example/`:
`dart analyze --fatal-infos`, `dart format --set-exit-if-changed .` and
`dart test`. In `tool/ciach_lints/`: `dart pub get` and `dart test`. In
`website/`, a Dart package of its own with its own workflow: `dart pub get`,
`dart analyze --fatal-infos`, `dart format --set-exit-if-changed .` and
`dart test`, which renders the committed assets and compares them.

When the base branch moves, merge it in; never rebase, amend or force-push a
pushed branch, even when asked to update it with `main`. A hunk that lands in a
file a split emptied belongs in the file its code moved to: port it there, then
drop the upstream copy. After resolving a conflict in prose, reread the section
against both sides, so that no heading or paragraph is lost.
