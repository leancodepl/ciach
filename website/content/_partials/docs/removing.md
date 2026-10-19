{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

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
- A class or mixin whose members are all unused and that only `with` or `implements` clauses name is reported and removed whole, from those clauses too, type arguments included. If other code names it, say as a type or after `extends`, or if it is the only mixin of `class A = B with M;`, only its members go, and the summary lists the emptied declaration.

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
