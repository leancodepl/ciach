{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

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
