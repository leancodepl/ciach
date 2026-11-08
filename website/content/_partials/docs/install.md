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

Globally, as a native `ciach` binary you can run from anywhere, or as a dev dependency that pins the version for the team and CI (then prefix commands with `dart run`). Requires Dart 3.10+ and analyzes with the SDK it runs with and with the version of the `analyzer` package that pub picks for it. When that analyzer doesn't support the Dart language version of a scanned package, ciach stops and says how to upgrade it.

```shell title="install" copy="dart install ciach"
dart install ciach
dart pub add --dev ciach
```

The native binary analyzes with the SDK of the `dart` on your `PATH` (an fvm or Flutter `dart` works too); `--dart <path>` picks another one.

As a dev dependency, ciach shares the project's `analyzer` version, so pub can't add it to a project whose other dependencies need an `analyzer` outside the range in ciach's `pubspec.yaml`. Install it globally there instead.
