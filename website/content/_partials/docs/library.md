{{!
  AI-Provenance:
    model: claude-fable-5-1
    harness: Claude Code
    plugins:
      - lean-ai-provenance
    skills:
      - mark-ai-provenance
}}

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
