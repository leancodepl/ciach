{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

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
