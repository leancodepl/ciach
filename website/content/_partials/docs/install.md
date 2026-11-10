{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

## Install

Globally, as a native `ciach` binary you can run from anywhere, or as a dev dependency that pins the version for the team and CI (then prefix commands with `dart run`). Requires Dart 3.10+ and analyzes with the SDK it runs with.

```shell title="install" copy="dart install ciach"
dart install ciach
dart pub add --dev ciach
```

The native binary runs the analysis server with the `dart` on your `PATH` (an fvm or Flutter `dart` works too); `--dart <path>` picks another one.
