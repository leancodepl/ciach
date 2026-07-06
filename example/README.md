# Example

This directory is a small, self-contained Dart package (`sample_pkg`) with a
deliberate mix of **used** and **unused** declarations. It doubles as the
integration-test fixture, so it is a real, runnable demonstration of the tool.

Run the finder against it from the repository root:

```console
$ dart run unused_declarations_finder example
```

Expected output:

```text
lib/sample.dart
  15:6   function     danglingFunction  (public)
  18:6   function     _danglingPrivate  (private)
  24:7   variable     unusedConstant  (public)
  32:13  constructor  UsedClass.named  (public)
  44:8   method       UsedClass.unusedMethod  (public)
  47:13  field        UsedClass._unusedField  (private)
  51:7   class        UnusedClass  (public)
  53:8   method       UnusedClass.orphanMethod  (public)
  60:3   constructor  Unconstructed.new  (public)
  66:10  method       Animal.sound  (public)

Found ... unused declarations ...
```

Things worth noticing:

- The widget-style declarations that *are* referenced (e.g. `UsedClass`,
  `registerHandlers`, `usedConstant`) are not reported.
- Constructors are reported as `Class.named` or `Class.new`.
- `Dog.sound` (an `@override`) is skipped by default; add `--overrides` to
  include it.
- Try `--no-public` to see only the highest-confidence, private dead code.
