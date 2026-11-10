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
- A primary constructor shares its class's references: a never-invoked one only surfaces once the class itself is dead.
- A package that doesn't analyze cleanly, from a stale `pub get` or errors, yields incomplete references.
- Bugs in the analysis server's reference search can report used code as unused, or make a query fail and land a declaration under "Not analyzed". [doc/upstream_bugs.md](https://github.com/leancodepl/ciach/blob/main/doc/upstream_bugs.md) lists the ones ciach has found and the SDK commits that fixed them.
