<!--
AI-Provenance:
  model: claude-fable-5-1
  harness: Claude Code
  plugins:
    - lean-ai-provenance
  skills:
    - mark-ai-provenance
-->

<div align="center">

[![Banner][banner-img]][leancode-landing]

</div>

# ciach 🔪

[![ciach pub.dev badge][pub-badge]][pub-badge-link]
[![Test status][test-badge]][test-badge-link]
[![License: Apache 2.0][license-badge]][license-badge-link]
[![style: leancode_lint][leancode-lint-badge]][leancode-lint-badge-link]
[![Pub Points][pub-points-badge]][pub-points-badge-link]

**Dead code detector for Dart and Flutter.** Finds declarations that are never
referenced — classes, functions, methods, fields, constants, enum values — and
can remove them for you.

🌐 **[Landing page][site]** — a tour of what ciach finds, skips, and removes.

*"Ciach!"* — pronounced **/t͡ɕax/** — is Polish for the sound of a clean chop,
the noise a knife makes right before something falls off.

## Installation

```bash
dart install ciach
```

That builds a native `ciach` you can run from anywhere. It runs the analysis
server with the `dart` on your `PATH` (an fvm or Flutter `dart` works too);
`--dart <path>` picks another one.

Or add it as a dev dependency, which pins the version for the team and CI:

```bash
dart pub add --dev ciach
dart run ciach
```

The examples below use a bare `ciach`; with the dev dependency, prefix them with
`dart run`.

ciach needs Dart 3.10 or newer. It analyzes with the SDK it runs on, so that
SDK has to be new enough for the code it scans.

## Usage

```bash
ciach                                     # the current package
ciach path/to/package                     # another package
ciach --no-public -f json                 # private declarations only, as JSON
ciach --also overrides,operators          # also what is skipped by default
ciach --remove                            # delete the findings, asking first
ciach --remove --force                    # …without asking
ciach -v                                  # explain each step
```

Run `dart pub get` first in every package ciach scans, nested ones included.
Otherwise ciach stops with exit code `2` and names the package; `--exclude`
skips a nested package instead. In a pub workspace, `pub get` in the root
covers every member.

The report goes to stdout. Progress, `-v` output, warnings, errors and the
`--remove` prompt go to stderr, so `ciach -f json | jq` works.

Exit codes: `0` success, `1` something found with `--set-exit-if-changed`, `2` a
usage or analysis error.

### Options

`ciach --help` describes every option. In short:

| Option | Default | Description |
| --- | --- | --- |
| `[path]` | `.` | The package to analyze. |
| `--config <path>` | auto | Read this config file instead of the discovered one. See [Configuration file](#configuration-file). |
| `--no-config` | off | Ignore the config file. |
| `--analysis-root <path>` | the scanned path | Count references from this whole directory, not just the scanned package. See [Monorepos](#monorepos). |
| `--[no-]public` | on | Report public declarations too. Off reports only private (`_`-prefixed) ones. |
| `--[no-]generated` | off | Scan generated files (`*.g.dart`, `*.freezed.dart`, `*.mocks.dart`, …) too. |
| `--exported-packages <glob>` | none | Packages that code outside the analysis imports, such as one published to pub.dev: their public API is not reported. Repeatable. See [Library packages](#library-packages). |
| `--[no-]project-config` | on | Read [entry points](#entry-points) and [generated files](#generated-files) from `pubspec.yaml`, `build.yaml`, `l10n.yaml`, `analysis_options.yaml` and `firebase.json`. |
| `--[no-]unused-translations` | on | Report the unused messages in the gen-l10n template file an `l10n.yaml` configures. Report-only: remove them from the ARB file yourself. |
| `--also <list>` | — | Also report what is [skipped by default](#what-it-skips-by-default): `overrides`, `operators`, `tojson`, `union-members`. |
| `--[no-]transitive` | on | Also report declarations used only by other dead code, naming what uses them. See [Transitively dead code](#transitively-dead-code). |
| `--[no-]set-exit-if-changed` | off; on in CI | Exit with `1` when anything is found. |
| `--[no-]ci` | auto | Use the CI defaults, or not. See [CI](#ci). |
| `--remove` | off | Remove the findings and delete empty files, after asking. See [Removing declarations](#removing-declarations). |
| `--force` | off | Skip the `--remove` prompt. |
| `-e, --exclude <glob>` | — | Skip these files: nothing in them is reported, but their references still count. Repeatable. |
| `-i, --include <glob>` | — | Scan only these files. The references in other files still count. Repeatable. |
| `--generated-glob <glob>` | — | Treat these files as generated: their references count, but nothing in them is reported or removed. For output without a suffix or banner, or code kept as is, like a vendored copy. Repeatable. |
| `-k, --kinds <list>` | all | Report only these kinds: `class, mixin, interface, enum, extension, extension-type, function, method, constructor, field, property, getter, setter, variable, constant, enum-value`. |
| `-f, --format <fmt>` | `text`; the service's on CI | `text`, `json`, `github`, `azure`, `teamcity`, `sarif`, `checkstyle` or `gitlab`. See [CI](#ci). |
| `-j, --concurrency <n>` | `16` | Reference queries to run at once. |
| `--[no-]color` | auto | Colorize the output. Honors `NO_COLOR`. |
| `--[no-]progress` | auto | Show progress on stderr. On for a terminal, off in CI. |
| `-v, --verbose` | off; on in CI | Explain the run on stderr: the config file and what it set, the settings, each phase, what was skipped and why, and what `--remove` touches. |
| `--dart <path>` | auto | The `dart` to run the analysis server with. |
| `--version` | — | Print the ciach version and exit. |
| `-h, --help` | — | Print the usage information. |

### Configuration file

Every option except `--help`, `--version`, `--config` and `--no-config` can
live in a `ciach.yaml` in the package root, keyed by its long name without the
`--`, plus `path` for the positional argument:

```yaml
public: false                     # --no-public
analysis-root: ..                 # --analysis-root
exported-packages: [packages/api] # see Library packages
exclude: ['test/**', 'tool/**']   # a repeatable option takes a list, or one string
kinds: [class, function, method]
format: github
set-exit-if-changed: true
entry-points:                     # config file only; see Entry points
  - name: bootstrap
    glob: 'lib/src/isolate.dart'
```

The command line wins over the file, and the file over the default. A
repeatable option on the command line replaces the file's list. An unknown key
or a wrong type is an error naming the file and the key.

Options from earlier versions are errors that say what to use instead. See
[MIGRATION.md](MIGRATION.md) for the list.

## What it reports

```
lib/greeting.dart
  15:6  function  danglingFunction  (public)
  31:3  method    Greeter._format   (private)

Found 2 unused declarations in 1 file (scanned 6 files, 44 declarations, 0.5s)
```

An unused class, mixin, extension, extension type or enum is reported once,
without its members. An enum that is used while none of its values are is
reported once too, and never removed: an enum needs at least one value.

### Doc-only findings

A dartdoc `[Xxx]` link resolves to a real declaration, so the analysis server
counts it as a reference. A comment mentioning something is not code calling
it, though, so declarations with no *code* references get a section of their
own, in every format:

```
Referenced only from doc comments (1) · not counted, never removed
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)
```

They never count toward `--set-exit-if-changed`, `--remove` never touches them,
and `-f github` gives them a `::notice` rather than a `::warning`. Drop the doc
link to have one reported as unused.

A type that only doc comments mention, and whose members are unused, is
reported once as a finding. `--remove` leaves it alone while doc comments still
link to it.

### Empty files

A file with nothing but comments and `library`, `import` or `part of`
directives gets a section too:

```
Empty files (2) · nothing but comments and library, import or part-of directives
lib/legacy/helpers.dart
lib/web.dart  (a conditional-import variant: remove its `if` clause and the file by hand)
```

These count toward `--set-exit-if-changed`. `--remove` deletes them with the
`import`s of them, except a conditional-import variant, which is left to you.

### Transitively dead code

A reference from a finding still counts as a use, so a helper called only by
dead code would show up only after that code is removed and ciach runs again.
ciach reports it in the same run, and dead cycles too: declarations that only
reference each other.

```
lib/report.dart
  12:6  function  _buildReport   (private)
  20:6  function  _formatRow     (private)  (only referenced from dead _buildReport (lib/report.dart:12))
  40:6  function  _ping          (private)  (only referenced from dead _pong (lib/report.dart:42))
  42:6  function  _pong          (private)  (only referenced from dead _ping (lib/report.dart:40))
```

Each such finding names what it is only referenced from, so a chain can be
judged by its root: `-f json` lists every finding a declaration depends on
under the `onlyReferencedFrom` key, and the other formats show the first and a
count.
A [report-only](#removing-declarations) finding stays in the code, so what it
references stays used. `--no-transitive` reports only what nothing references
at all; the rest shows up after a removal and another run.

### Not analyzed

If the analysis server fails on a declaration or a file, the run goes on. That
code is kept and listed under "Not analyzed" (`problems` in JSON); `-v` adds
the stack traces.

## What it skips by default

Each of these is a known source of false positives. Where there is a flag, it
opts back in at that cost.

| Skipped | Why | Flag |
| --- | --- | --- |
| `main` | the entry point is never unused | — |
| `testExecutable` in a `flutter_test_config.dart` | `flutter test` calls it | — |
| Entry points from the [project config](#entry-points) | a framework or a tool calls them | `--no-project-config` |
| `@override` members | often reached polymorphically or by a framework (`build`, `initState`, `==`, …), which a name-based search misses. One that overrides a dead member is dead too, and `--remove` [takes both](#removing-declarations) | `--also overrides` |
| Operator overloads | the server doesn't resolve `a + b` back to the declaration, so a used operator is flagged every time | `--also operators` |
| `call` methods | `obj(…)` is unresolvable the same way | — |
| Declarations and files marked [`// ciach:ignore`](#ignore-markers) | they are kept on purpose | — |
| `@pragma('vm:entry-point')` | reachable from native code or reflection | — |
| `@JSExport`, and the public members of a `@JSExport` class | JavaScript can call them | — |
| `test_…` methods of a `@reflectiveTest` class | they run through `dart:mirrors` | — |
| Generated files | by filename, by a generated-code banner, by the [project config](#generated-files) and by `--generated-glob`. Still read, so a declaration used only from a `.g.dart` is not misreported | `--generated` |
| `toJson()` | `jsonEncode(obj)` calls it by dynamic dispatch, leaving no reference | `--also tojson` |
| Type parameters | always used within their scope | — |
| dartdoc `[Xxx]` links | not a code reference; reported as [doc-only](#doc-only-findings) instead | — |

The variants of a conditional import, like `io.dart` and `web.dart` in
`import 'io.dart' if (dart.library.js_interop) 'web.dart';`, are checked
together: a public declaration shares the references of its namesakes in the
other variants, and is reported and removed only with them. A variant whose
other variant is not scanned is not checked.

Private constructors are **not** skipped: an unused `ClassName._` is dead code
like any other. A sole `ClassName._()` with no parameters, the classic
prevent-instantiation marker, comes with a hint suggesting `abstract final
class` instead. [example/](example) demonstrates each case.

### Entry points

Some declarations are only called from code a tool generates, so nothing in the
package references them: `flutter test` runs `testExecutable`, flutter_tools
calls `MyPlugin.registerWith()`. ciach knows about `main` and `testExecutable`,
and reads these from the project's own config files:

| Source | Entry point |
| --- | --- |
| `build.yaml` builders | the functions under `builder_factories` or `builder_factory` |
| `pubspec.yaml` plugin | `registerWith` on each platform's `dartPluginClass` and on the web `pluginClass` |
| `dart_frog` | `onRequest`, `middleware`, `init`, `run` |
| `serverpod` | the classes that extend `Endpoint`, and their public methods |
| `analysis_server_plugin`, or a package an `analysis_options.yaml` under the root loads as a plugin by `path:` | `plugin` in `lib/main.dart` |
| `custom_lint_builder` | `createPlugin` in `lib/<package>.dart` |

List any other entry points under `entry-points:` in `ciach.yaml`:

```yaml
entry-points:
  - name: MyHost.callback         # a member: `Type.member`, no type parameters
    glob: 'lib/my_host.dart'      # one glob or a list; omit for any file
  - name: bootstrap               # a top-level declaration
    glob: 'lib/src/isolate.dart'
```

A matching declaration is neither reported nor removed. A member rule also
keeps its type, while the type's other members are still checked. A rule that
names a class or extension type also keeps its unnamed constructor, but not its
named ones. Name a constructor the way the report does: `MyWidget.new` or
`MyWidget.named`. `-v` names each skipped entry point.

### Ignore markers

A `// ciach:ignore` comment keeps a declaration from being reported or removed:

```dart
// ciach:ignore
void keptForTheWidgetbook() {}        // the declaration on the next line

/// Its doc comment and annotations may sit around the marker.
// ciach:ignore
@visibleForTesting
void alsoKept() {}

void keptToo() {} // ciach:ignore    // after code: the one named on its line

// ciach:ignore-start
class Catalog {                       // everything named in the range
  void member() {}
}
// ciach:ignore-end
```

`// ciach:ignore-file` anywhere in a file keeps the whole file: ciach still
counts the uses of other code in it, but reports and changes nothing in it.

Any declaration can be marked, enum values and constructors included. Marking a
member also keeps its type, while the type's other members are still checked.
Free text may follow a marker, as a reason. Only `//` comments count: a marker
in a doc comment, a block comment or a string does nothing. ciach warns about a
marker that keeps nothing, an unclosed range, and an unknown `// ciach:` word,
and `-v` names each kept declaration.

### Generated files

Besides files named like generated code or carrying a generated-code banner,
ciach treats these as generated:

- The files build_runner writes into the source tree, read from the outputs
  the applied builders declare in `build.yaml` and every `build.<name>.yaml`.
- The files `flutter gen-l10n` writes, as `l10n.yaml` configures them. The
  template file is scanned instead, and its unused messages reported;
  `--no-unused-translations` treats it as generated too.
- The `firebase_options*.dart` files `flutterfire configure` writes, as
  `firebase.json` records them.

Every package under the scanned path is read from its own files, so scanning the
root of a pub workspace or monorepo covers all of its members.

## Removing declarations

`--remove` deletes every reported declaration, doc comment and annotations
included, after showing what it is about to remove and asking:

```
Found 4 unused declarations in 2 files (scanned 6 files, 44 declarations, 0.5s)
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 2 files.
```

`--force` skips the prompt. With no terminal to confirm on and no `--force`,
nothing is removed. Run `dart format` afterward: removal cuts along the
analyzer's syntax, so `int a = 1, b = 2;` loses just `b` or the whole
statement, but it doesn't tidy up spacing.

Removal acts on whatever the finder reports, so it inherits the same
false-positive risk, which `--also overrides,operators` widens considerably.
Review the diff, as you would after any automated refactor.

What goes with a removed declaration:

- Its overrides, wherever they live: a call through any subclass would have
  referenced the member, so they are dead too.
- A file left with only `library`, `import` or `part of` directives, an
  [empty file](#empty-files) found before removal, and the `import`s of them
  elsewhere. A file that still `export`s or owns a `part` stays.
- A class or mixin whose members are all unused and that only `with` or
  `implements` clauses name is reported and removed whole, from those clauses
  too, type arguments included. If other code names it, say as a type or
  after `extends`, or if it is the only mixin of `class A = B with M;`, only
  its members go, and the summary lists the emptied declaration.

A plain `//` comment right above a removed declaration stays, because it may be
about the code around it rather than the declaration. The summary lists each
such comment with its line in the changed file, so you can check whether it
still belongs. A comment with a blank line after it is not listed, and neither
is a comment for a tool, such as `// ciach:ignore-end` or `// dart format on`.

An `// ignore:`, `// expect_lint:` or `// cspell:disable-next-line` comment
right above a removed declaration goes with it, since it only applies to the
next line. So does a `//` comment at the end of the last line of a removed
declaration, or of a removed `import`. A comment for a tool there, such as
`// coverage:ignore-start`, stays, so the range it opens or closes keeps both
ends.

Findings that cannot be removed without breaking the build are **report-only**,
marked `unsafe to auto-remove — remove manually` and left in place:

| Report-only finding | Why |
| --- | --- |
| A sealed member matched only by type patterns (`--also union-members`) | its `case` arms would need rewriting |
| A used enum whose values are all unused | `enum E {}` doesn't compile |
| The sole constructor of a live class with `final` fields, or whose superclass needs constructor arguments | the implicit default constructor can't replace it |
| A primary constructor or its declaring parameters | only part of the class header |
| A member whose override is a declaring parameter, or is in a file the run didn't scan | that override can't be deleted, and would be left overriding nothing |
| A gen-l10n message | gen-l10n would generate it again from the ARB file |
| A type that only doc comments mention | the links would dangle |

## Packages and monorepos

### Library packages

By default, ciach checks the API of every package, which suits an app. But it
can't see importers outside the analysis. So list in `exported-packages` the
packages that code outside the analysis imports, such as one published to
pub.dev or used as a git dependency. ciach then doesn't report what other
packages can import from them: the libraries under `lib/` outside `lib/src/`,
what they export (`show`/`hide` respected), and the members of any type those
hand out, say in a return type, a field or a supertype.

Each entry is a glob of a package directory, relative to the scanned path.
`'**'` matches every package:

```yaml
# ciach.yaml
exported-packages: [packages/shared_api]
```

`-v` says which packages are left out.

### Monorepos

In a monorepo where sibling packages depend on this one by `path:`, their calls
are invisible, so a declaration used only from them reads as dead.
`--analysis-root` widens where references are counted, and nothing else:

```bash
ciach pkgs/core --analysis-root .    # scan pkgs/core, count uses from the whole repo
```

What is scanned, reported and removed, `--include`/`--exclude` and `ciach.yaml`
discovery stay on the scanned package. The root must contain that package. The
whole repository gets analyzed, so the run is slower.

A pub workspace needs no setting: the analysis covers every member already.
Without one, `-v` notes a package in the same git repository that depends on the
scanned one by `path:`, and names the `--analysis-root` that would count it.

## CI

ciach detects CI from the environment (`CI`, or a service's own variable such as
`GITHUB_ACTIONS`) and changes its defaults there:

- `--set-exit-if-changed` on: the job fails on findings.
- `--verbose` on: the log explains the run.
- `--progress` off.
- `--format github` on GitHub Actions, `azure` on Azure Pipelines, `teamcity` on
  TeamCity.

An explicit option still wins. `--no-ci` keeps the local defaults on a runner,
`--ci` applies the CI ones elsewhere.

### GitHub Actions

```yaml
- run: dart pub get
- run: dart run ciach
```

Each finding becomes a `::warning` annotation on the PR diff, and the job fails
when anything is found. Report paths start at the repository root wherever ciach
runs from: on GitHub Actions, GitLab CI and Azure Pipelines ciach finds the root
from the checkout the service names. Elsewhere they start at the current
directory, so run ciach from the repository root; `ciach app` still works.

### Azure Pipelines and TeamCity

```yaml
- script: dart pub get && dart run ciach
```

On Azure Pipelines each finding becomes a warning in the run's summary (doc-only
ones too: Azure has nothing below a warning). On TeamCity each one is an
inspection on the build's Inspections tab, a doc-only one a weak warning. Run
ciach from the checkout root on TeamCity, which names no checkout to it.

### Reports for other tools

Three formats are files for another tool to import, so redirect them:

| Format | For |
| --- | --- |
| `sarif` | GitHub code scanning (`github/codeql-action/upload-sarif`), Azure DevOps, SonarQube and other SARIF dashboards. |
| `checkstyle` | Jenkins Warnings Next Generation and other Checkstyle report plugins. |
| `gitlab` | A GitLab Code Quality report, shown on the merge request. |

```yaml
ciach:
  script: dart run ciach -f gitlab > gl-code-quality-report.json
  artifacts:
    reports:
      codequality: gl-code-quality-report.json
```

Unused findings and empty files are warnings (`minor` in GitLab), doc-only
findings a severity lower. GitLab fingerprints leave out the line, so a finding
that only moved is not reported as new.

## Limitations

ciach is a static, reference-based heuristic, so review its output rather than
deleting blindly:

- **A published package's consumers** are invisible, which is why its API is
  [left out](#library-packages). In a monorepo, [`--analysis-root`](#monorepos)
  recovers uses from a sibling package.
- **Reflection, dynamic invocation, and names used only from generated code you
  excluded** are invisible to a reference search.
- **Other entry points**, such as isolate entry points and native callbacks,
  have to be listed under [`entry-points`](#entry-points) or marked with
  `@pragma('vm:entry-point')`.
- **A primary constructor shares its class's references**: a never-invoked one
  only surfaces once the class itself is dead.
- **A package that doesn't analyze cleanly**, from a stale `pub get` or errors,
  yields incomplete references.
- **Bugs in the analysis server's reference search** can report used code as
  unused, or make a query fail and land a declaration under "Not analyzed".
  [doc/upstream_bugs.md][upstream-bugs] lists the ones ciach has found and the
  SDK commits that fixed them.

## Performance

The time goes to the analysis server: it analyzes the whole package once per
run, tens of seconds for a large Flutter app, then answers one reference query
per declaration, `-j` of them at a time. The lever is how much you ask for.
`--no-public` is by far the cheapest mode, since a private declaration's query
searches one library instead of the whole workspace, and it surfaces the
highest-confidence dead code anyway. `--include` and `--exclude` narrow the
scan while still counting references from everywhere.

## Library usage

The finder is also available programmatically:

```dart
import 'package:ciach/ciach.dart';

final result = await Ciach(
  FinderOptions(rootPath: 'path/to/package', includePublic: false),
).run();
for (final decl in result.unused) {
  print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
}
```

ciach logs through [`package:logging`](https://pub.dev/packages/logging), with
loggers such as `ciach.finder` and `ciach.lsp`. It never configures the root
logger; listen on `Logger.root.onRecord` to see the records.

## Development

```bash
dart pub get
dart analyze
dart test          # spins up a real analysis server against the example/ package
```

The implementation lives under `lib/src/`; the CLI entry point is `bin/`.
`lib/src/finder.dart` runs a scan as a pipeline, and its doc comment maps the
directories under `lib/src/` to the stages. Tests mirror that layout under
`test/`; `test/finder/` runs the whole finder against the `example/` package.

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE).

---

## 🛠️ Maintained by LeanCode

<div align="center">

  [<img src="https://leancodepublic.blob.core.windows.net/public/wide.png" alt="LeanCode Logo" height="100" />][leancode-landing]

</div>

This package is built with 💙 by **[LeanCode][leancode-landing]**.
We are **top-tier experts** focused on Flutter Enterprise solutions.

### Why LeanCode?

- **Creators of [Patrol][patrol-landing]** – the next-gen testing framework for Flutter.
- **Battle-Tested** – we run `ciach` across our own Flutter and Dart codebases to keep them free of dead code.
- **Full-Cycle Product Development** – we take your product from scratch to long-term maintenance.

<div align="center">
  <br />

  **Need help with your Flutter project?**

  [**👉 Hire our team**][leancode-estimate]
  &nbsp;&nbsp;•&nbsp;&nbsp;
  [Check our other packages][leancode-packages]

</div>

[site]: https://ciach.leancode.co/
[upstream-bugs]: https://github.com/leancodepl/ciach/blob/main/doc/upstream_bugs.md

[pub-badge]: https://img.shields.io/pub/v/ciach?style=for-the-badge&logo=dart
[pub-badge-link]: https://pub.dev/packages/ciach

[test-badge]: https://img.shields.io/github/actions/workflow/status/leancodepl/ciach/test.yml?branch=main&style=for-the-badge&logo=github
[test-badge-link]: https://github.com/leancodepl/ciach/actions/workflows/test.yml

[license-badge]: https://img.shields.io/github/license/leancodepl/ciach?style=for-the-badge
[license-badge-link]: https://github.com/leancodepl/ciach/blob/main/LICENSE

[leancode-lint-badge]: https://img.shields.io/badge/style-leancode__lint-f0ff00?style=for-the-badge
[leancode-lint-badge-link]: https://pub.dev/packages/leancode_lint

[pub-points-badge]: https://img.shields.io/pub/points/ciach?style=for-the-badge&logo=dart
[pub-points-badge-link]: https://pub.dev/packages/ciach/score

[leancode-landing]: https://leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[leancode-estimate]: https://leancode.co/get-estimate?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[leancode-packages]: https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads
[patrol-landing]: https://patrol.leancode.co/?utm_source=github.com&utm_medium=referral&utm_campaign=ciach
[banner-img]: https://raw.githubusercontent.com/leancodepl/ciach/refs/heads/main/doc/imgs/banner.png
