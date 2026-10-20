{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

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
