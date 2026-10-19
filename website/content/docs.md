---
title: Docs
description: How to install, configure and run ciach, how to read its report, what it skips and why, how --remove stays safe, the library API and answers to common questions.
lead: Install, configure and run ciach, and read its findings with confidence.
---

<!--
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
-->

## Install

Globally, as a native `ciach` binary you can run from anywhere, or as a dev dependency that pins the version for the team and CI (then prefix commands with `dart run`). Requires Dart 3.10+ and analyzes with the SDK it runs with.

```shell title="install" copy="dart install ciach"
dart install ciach
dart pub add --dev ciach
```

The native binary runs the analysis server with the `dart` on your `PATH` (an fvm or Flutter `dart` works too); `--dart <path>` picks another one.

## Running ciach

```console title="usage"
$ dart install ciach
$ ciach                                  # current package
$ ciach path/to/package                  # another package
$ ciach --no-public -f json              # private-only, as JSON
$ ciach -f github --set-exit-if-changed  # CI: annotations, non-zero on finds
$ ciach --remove                         # delete findings, asks first
```

Run `dart pub get` first in every package ciach scans, nested ones included. Otherwise ciach stops with exit code `2` and names the package; `--exclude` skips a nested package instead. In a pub workspace, `pub get` in the root covers every member.

The report goes to stdout. Progress, `-v` output, warnings, errors and the `--remove` prompt go to stderr, so `ciach -f json | jq` works.

Exit codes: `0` success, `1` something found with `--set-exit-if-changed`, `2` a usage or analysis error.

A large Flutter app takes tens of seconds to analyze. `--no-public` is by far the cheapest mode, and `--include` and `--exclude` narrow the scan while references are still counted from everywhere.

## Reading the report

```console wrap=false
lib/user.dart
  12:13  constructor  UsedClass.named  (public)
  27:14  property     UsedClass.shout  (public)
  36:8   method       UsedClass.unusedMethod  (public)
  39:13  field        UsedClass._unusedField  (private)

Found 4 unused declarations in 1 file (scanned 1 file, 12 declarations, 1.2s)
```

An unused class, mixin, extension, extension type or enum is reported once, without its members. An enum that is used while none of its values are is reported once too, and never removed: an enum needs at least one value.

### Doc-only findings

A declaration that only dartdoc `[Xxx]` links mention gets a section of its own, in every format:

```console wrap=false
Referenced only from doc comments (1) · not counted, never removed
lib/greeting.dart
  40:6  function  docOnlyMentioned  (public)
```

They never count toward `--set-exit-if-changed`, `--remove` never touches them, and `-f github` gives them a `::notice` rather than a `::warning`. Drop the doc link to have one reported as unused.

A type that only doc comments mention, and whose members are unused, is reported once as a finding. `--remove` leaves it alone while doc comments still link to it.

### Empty files

A file with nothing but comments and `library`, `import` or `part of` directives gets a section too:

```console wrap=false
Empty files (2) · nothing but comments and library, import or part-of directives
lib/legacy/helpers.dart
lib/web.dart  (a conditional-import variant: remove its `if` clause and the file by hand)
```

These count toward `--set-exit-if-changed`. `--remove` deletes them with the `import`s of them, except a conditional-import variant, which is left to you.

### Transitively dead code

A declaration used only by other dead code is reported in the same run, and so are dead cycles: declarations that only reference each other.

```console wrap=false
lib/report.dart
  12:6  function  _build      (private)
  20:6  function  _formatRow  (private)  (only referenced from dead _build (lib/report.dart:12))
  40:6  function  _ping       (private)  (only referenced from dead _pong (lib/report.dart:42))
  42:6  function  _pong       (private)  (only referenced from dead _ping (lib/report.dart:40))
```

Each such finding names what it is only referenced from, so a chain can be judged by its root: `-f json` lists every finding a declaration depends on under the `onlyReferencedFrom` key, and the other formats show the first and a count. A report-only finding stays in the code, so what it references stays used. `--no-transitive` reports only what nothing references at all; the rest shows up after a removal and another run.

### Not analyzed

If the analysis server fails on a declaration or a file, the run goes on. That code is kept and listed under "Not analyzed" (`problems` in JSON); `-v` adds the stack traces.

## What it skips by default

Each of these is a known source of false positives. Where there is a flag, it opts back in at that cost.

| Skipped | Why | Flag |
| --- | --- | --- |
| `main` | the entry point is never unused | — |
| `testExecutable` in a `flutter_test_config.dart` | `flutter test` calls it | — |
| Entry points from the project config | a framework or a tool calls them | `--no-project-config` |
| `@override` members | often reached polymorphically or by a framework (`build`, `initState`, `==`, …), which a name-based search misses. One that overrides a dead member is dead too, and `--remove` takes both | `--also overrides` |
| Operator overloads | the server doesn't resolve `a + b` back to the declaration, so a used operator is flagged every time | `--also operators` |
| Declarations and files marked `// ciach:ignore` | they are kept on purpose | — |
| `@pragma('vm:entry-point')` | reachable from native code or reflection | — |
| `@JSExport`, and the public members of a `@JSExport` class | JavaScript can call them | — |
| `test_…` methods of a `@reflectiveTest` class | they run through `dart:mirrors` | — |
| Generated files | by filename, by a generated-code banner, by the project config and by `--generated-glob`. Still read, so a declaration used only from a `.g.dart` is not misreported | `--generated` |
| `toJson()` | `jsonEncode(obj)` calls it by dynamic dispatch, leaving no reference | `--also tojson` |
| Type parameters | always used within their scope | — |
| dartdoc `[Xxx]` links | not a code reference; reported as doc-only instead | — |

The variants of a conditional import, like `io.dart` and `web.dart` in `import 'io.dart' if (dart.library.js_interop) 'web.dart';`, are checked together: a public declaration shares the references of its namesakes in the other variants, and is reported and removed only with them. A variant whose other variant is not scanned is not checked.

Private constructors are not skipped: an unused `ClassName._` is dead code like any other. A sole `ClassName._()` with no parameters, the classic prevent-instantiation marker, comes with a hint suggesting `abstract final class` instead.

### Entry points

Some declarations are only called from code a tool generates, so nothing in the package references them: `flutter test` runs `testExecutable`, flutter_tools calls `MyPlugin.registerWith()`. ciach knows about `main` and `testExecutable`, and reads these from the project's own config files:

| Source | Entry point |
| --- | --- |
| `build.yaml` builders | the functions under `builder_factories` or `builder_factory` |
| `pubspec.yaml` plugin | `registerWith` on each platform's `dartPluginClass` and on the web `pluginClass` |
| `dart_frog` | `onRequest`, `middleware`, `init`, `run` |
| `serverpod` | the classes that extend `Endpoint`, and their public methods |
| `analysis_server_plugin`, or a package an `analysis_options.yaml` under the root loads as a plugin by `path:` | `plugin` in `lib/main.dart` |
| `custom_lint_builder` | `createPlugin` in `lib/<package>.dart` |

List any other entry points under `entry-points:` in `ciach.yaml`:

```yaml title="ciach.yaml"
entry-points:
  - name: MyHost.callback         # a member: `Type.member`, no type parameters
    glob: 'lib/my_host.dart'      # one glob or a list; omit for any file
  - name: bootstrap               # a top-level declaration
    glob: 'lib/src/isolate.dart'
```

A matching declaration is neither reported nor removed. A member rule also keeps its type, while the type's other members are still checked. A rule that names a class or extension type also keeps its unnamed constructor, but not its named ones. Name a constructor the way the report does: `MyWidget.new` or `MyWidget.named`. `-v` names each skipped entry point.

### Ignore markers

A `// ciach:ignore` comment keeps a declaration from being reported or removed:

```dart copy=false
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

`// ciach:ignore-file` anywhere in a file keeps the whole file: ciach still counts the uses of other code in it, but reports and changes nothing in it.

Any declaration can be marked, enum values and constructors included. Marking a member also keeps its type, while the type's other members are still checked. Free text may follow a marker, as a reason. Only `//` comments count: a marker in a doc comment, a block comment or a string does nothing. ciach warns about a marker that keeps nothing, an unclosed range, and an unknown `// ciach:` word, and `-v` names each kept declaration.

### Generated files

Besides files named like generated code or carrying a generated-code banner, ciach treats these as generated:

- The files build_runner writes into the source tree, as `build.yaml` configures them.
- The files `flutter gen-l10n` writes, as `l10n.yaml` configures them. The template file is scanned instead, and its unused messages reported; `--no-unused-translations` treats it as generated too.
- The `firebase_options*.dart` files `flutterfire configure` writes, as `firebase.json` records them.

Every package under the scanned path is read from its own files, so scanning the root of a pub workspace or monorepo covers all of its members.

## Removing dead code

`--remove` deletes every reported declaration, doc comment and annotations included, after showing what it is about to remove and asking:

```console wrap=false
Found 4 unused declarations in 2 files (scanned 6 files, 44 declarations, 0.5s)
Remove 4 unused declarations? [y/N] y
Removed 4 unused declarations from 2 files.
```

`--force` skips the prompt. With no terminal to confirm on and no `--force`, nothing is removed. Run `dart format` afterward.

Removal acts on whatever the finder reports, so it inherits the same false-positive risk, which `--also overrides,operators` widens considerably. Review the diff, as you would after any automated refactor.

### What goes with a removed declaration

- Its overrides, wherever they live: a call through any subclass would have referenced the member, so they are dead too.
- A file left with only `library`, `import` or `part of` directives, an empty file found before removal, and the `import`s of them elsewhere. A file that still `export`s or owns a `part` stays.
- A class or mixin whose members are all unused and that only `with` or `implements` clauses name is reported and removed whole, from those clauses too. If other code names it, say as a type or after `extends`, if it is generic, or if it is the only mixin of `class A = B with M;`, only its members go, and the summary lists the emptied declaration.

### Comments next to removed code

A plain `//` comment right above a removed declaration stays, because it may be about the code around it, and the summary lists it with its line so you can check whether it still belongs. An `// ignore:`, `// expect_lint:` or `// cspell:disable-next-line` comment above the declaration, and a `//` comment at the end of its last line, go with it. A comment for a tool, such as `// coverage:ignore-start`, always stays.

### Report-only findings

Findings that cannot be removed without breaking the build are report-only, marked `unsafe to auto-remove — remove manually` and left in place.

| Report-only finding | Why |
| --- | --- |
| A sealed member matched only by type patterns (`--also union-members`) | its `case` arms would need rewriting |
| A used enum whose values are all unused | `enum E {}` doesn't compile |
| The sole constructor of a live class with `final` fields, or whose superclass needs constructor arguments | the implicit default constructor can't replace it |
| A primary constructor or its declaring parameters | only part of the class header |
| A member whose override is a declaring parameter, or is in a file the run didn't scan | that override can't be deleted, and would be left overriding nothing |
| A gen-l10n message | gen-l10n would generate it again from the ARB file |
| A type that only doc comments mention | the links would dangle |

## Options

| Flag | What it does |
| --- | --- |
| `--no-public` | Report private declarations only. Cheapest mode. |
| `--exported-packages <glob>` | Packages that code outside the analysis imports, such as one published to pub.dev, whose API is not reported. |
| `--remove`, `--force` | Delete what was found after confirming. `--force` skips the prompt. |
| `-f <format>` | text, json, github, azure, teamcity, sarif, checkstyle or gitlab. |
| `--set-exit-if-changed` | Exit 1 when anything is found. On by default in CI. |
| `-k`, `--kinds` | Restrict to declaration kinds, e.g. `class,function,method`. |
| `-i`, `-e` | Include or exclude file globs. References are still counted from everywhere. |
| `--analysis-root` | Count references from a whole monorepo, not just the scanned package. What is scanned and removed is unchanged. |
| `--no-transitive` | Report only declarations that nothing uses. By default, a declaration used only by other dead code is reported too, naming what uses it. |
| `--also overrides,operators,tojson,union-members` | Opt back into a category skipped by default. |
| `--generated` | Scan generated files too. |
| `-v` | Narrate the run on stderr with timings. |

`ciach --help` describes every option; so does the [options table](https://github.com/leancodepl/ciach#options) in the README.

## Configuration file

Every option except `--help`, `--version`, `--config` and `--no-config` can live in a `ciach.yaml` in the package root, keyed by its long name without the `--`, plus `path` for the positional argument:

```yaml title="ciach.yaml"
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

The command line wins over the file, and the file over the default. A repeatable option on the command line replaces the file's list. An unknown key or a wrong type is an error naming the file and the key. Discovery looks in the analyzed package root only, so each package in a monorepo owns its config; `--config <path>` reads one from elsewhere, `--no-config` ignores it.

Options from earlier versions are errors that say what to use instead. [MIGRATION.md](https://github.com/leancodepl/ciach/blob/main/MIGRATION.md) lists them.

## Packages and monorepos

### Library packages

By default, ciach checks the API of every package, which suits an app. But it can't see importers outside the analysis. So list in `exported-packages` the packages that code outside the analysis imports, such as one published to pub.dev or used as a git dependency. ciach then doesn't report what other packages can import from them: the libraries under `lib/` outside `lib/src/`, what they export (`show`/`hide` respected), and the members of any type those hand out, say in a return type, a field or a supertype.

Each entry is a glob of a package directory, relative to the scanned path. `'**'` matches every package:

```yaml title="ciach.yaml"
exported-packages: [packages/shared_api]
```

`-v` says which packages are left out.

### Monorepos

In a monorepo where sibling packages depend on this one by `path:`, their calls are invisible, so a declaration used only from them reads as dead. `--analysis-root` widens where references are counted, and nothing else:

```console title="monorepo"
$ ciach pkgs/core --analysis-root .    # scan pkgs/core, count uses from the whole repo
```

What is scanned, reported and removed, `--include`/`--exclude` and `ciach.yaml` discovery stay on the scanned package. The root must contain that package. The whole repository gets analyzed, so the run is slower.

A pub workspace needs no setting: the analysis covers every member already. Without one, `-v` notes a package in the same git repository that depends on the scanned one by `path:`, and names the `--analysis-root` that would count it.

## CI

ciach detects CI from the environment (`CI`, or a service's own variable such as `GITHUB_ACTIONS`) and changes its defaults there:

- `--set-exit-if-changed` on: the job fails on findings.
- `--verbose` on: the log explains the run.
- `--progress` off.
- `--format github` on GitHub Actions, `azure` on Azure Pipelines, `teamcity` on TeamCity.

An explicit option still wins. `--no-ci` keeps the local defaults on a runner, `--ci` applies the CI ones elsewhere.

### GitHub Actions

```yaml title=".github/workflows/test.yml"
- run: dart pub get
- run: dart run ciach
```

Each finding becomes a `::warning` annotation on the PR diff, and the job fails when anything is found. Report paths start at the repository root wherever ciach runs from: on GitHub Actions, GitLab CI and Azure Pipelines ciach finds the root from the checkout the service names. Elsewhere they start at the current directory, so run ciach from the repository root; `ciach app` still works.

### Azure Pipelines and TeamCity

```yaml copy=false
- script: dart pub get && dart run ciach
```

On Azure Pipelines each finding becomes a warning in the run's summary (doc-only ones too: Azure has nothing below a warning). On TeamCity each one is an inspection on the build's Inspections tab, a doc-only one a weak warning. Run ciach from the checkout root on TeamCity, which names no checkout to it.

### Reports for other tools

Three formats are files for another tool to import, so redirect them:

| Format | For |
| --- | --- |
| `sarif` | GitHub code scanning (`github/codeql-action/upload-sarif`), Azure DevOps, SonarQube and other SARIF dashboards. |
| `checkstyle` | Jenkins Warnings Next Generation and other Checkstyle report plugins. |
| `gitlab` | A GitLab Code Quality report, shown on the merge request. |

```yaml title=".gitlab-ci.yml"
ciach:
  script: dart run ciach -f gitlab > gl-code-quality-report.json
  artifacts:
    reports:
      codequality: gl-code-quality-report.json
```

Unused findings and empty files are warnings (`minor` in GitLab), doc-only findings a severity lower. GitLab fingerprints leave out the line, so a finding that only moved is not reported as new.

## Compared with the analyzer

The Dart analyzer already flags unused private declarations through `unused_element` and friends, one library at a time. ciach starts where that stops.

| | `dart analyze` | `ciach` |
| --- | --- | --- |
| Unused private declarations | ✓ | ✓ |
| Unused public declarations | — | ✓ |
| References followed across libraries | — | ✓ |
| Removes what it finds | — | ✓ |
| GitHub annotations on the pull request | — | ✓ |
| JSON output | ✓ | ✓ |

Both resolve references the same way, because ciach asks the analysis server. The difference is scope and the removal step. Dart Code Metrics covers unused code as well, as part of a larger commercial toolset.

## Limitations

ciach is a static, reference-based heuristic, so review its output rather than deleting blindly:

- A published package's consumers are invisible, which is why its API is left out with `exported-packages`. In a monorepo, `--analysis-root` recovers uses from a sibling package.
- Reflection, dynamic invocation, and names used only from generated code you excluded are invisible to a reference search.
- Other entry points, such as isolate entry points and native callbacks, have to be listed under `entry-points` or marked with `@pragma('vm:entry-point')`.
- A primary constructor shares its class's references: a never-invoked one only surfaces once the class itself is dead.
- A package that doesn't analyze cleanly, from a stale `pub get` or errors, yields incomplete references.
- Bugs in the analysis server's reference search can report used code as unused, or make a query fail and land a declaration under "Not analyzed". [doc/upstream_bugs.md](https://github.com/leancodepl/ciach/blob/main/doc/upstream_bugs.md) lists the ones ciach has found and the SDK commits that fixed them.

## Library API

The finder behind the CLI is exported from `package:ciach/ciach.dart`. Options mirror the flags; the result carries every finding with file, line, kind and qualified name, and doc-only findings in their own list.

```dart title="tool/dead_code.dart"
final result = await Ciach(
  FinderOptions(rootPath: 'path/to/package', includePublic: false),
).run();

for (final decl in result.unused) {
  print('${decl.filePath}:${decl.line} ${decl.qualifiedName}');
}
```

## FAQ

<Faq />
