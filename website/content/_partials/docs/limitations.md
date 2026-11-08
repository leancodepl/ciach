{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

## Limitations

ciach is a static, reference-based heuristic, so review its output rather than deleting blindly:

- A published package's consumers are invisible, which is why its API is left out with `exported-packages`. In a monorepo, `--analysis-root` recovers uses from a sibling package.
- Reflection, dynamic invocation, and names used only from generated code you excluded are invisible to a reference search.
- Other entry points, such as isolate entry points and native callbacks, have to be listed under `entry-points` or marked with `@pragma('vm:entry-point')`.
- A package that doesn't analyze cleanly, from a stale `pub get` or errors, yields incomplete references. Each file with a compile error is listed under "Not analyzed".
