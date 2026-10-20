{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

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
