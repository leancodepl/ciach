# Analysis server bugs found by ciach

ciach used to ask the Dart analysis server for the references of every
declaration in a project, so it ran into reference-search bugs that an editor
rarely hits. These are the ones we reported to the Dart SDK. ciach now finds
references with `package:analyzer` itself, so these bugs don't affect it.

The Dart SDK takes changes through Gerrit rather than pull requests, so each
fix links to its CL and to the commit it landed as.

| Issue | Bug | Fix | Fixed by |
| --- | --- | --- | --- |
| [dart-lang/sdk#63903][63903] | Find All References returns nothing for a getter, field or method referenced only from an object pattern (`A(foo: _)`) in another file | [CL 528540][cl-528540], [`e837b59`][e837b59] | ✅ us ([@Komoszek]) |
| [dart-lang/sdk#63944][63944] | Find References, rename and Extract Method miss a dot shorthand (`.foo`) when a local variable of the same name is in scope | [CL 530160][cl-530160], [`1cc49b4`][1cc49b4] | ✅ us ([@Komoszek]) |
| [dart-lang/sdk#64422][64422] | `textDocument/references` throws for an override of an `Object` member once the library has a class with a primary constructor | [CL 558400][cl-558400], [`767a1e2`][767a1e2] | the Dart team |
| [dart-lang/sdk#64629][64629] | Find All References on an operator misses its uses in other files | [CL 565940][cl-565940], [`e7e1ecc`][e7e1ecc] | ✅ us ([@Komoszek]) |
| [dart-lang/sdk#64630][64630] | Find All References and Go to Definition don't connect an operator in a relational pattern (`case < const A()`) to its declaration | [CL 567884][cl-567884], [`820e2b3`][820e2b3] | ✅ us ([@Komoszek]) |

The same list is shown on [ciach.leancode.co](https://ciach.leancode.co/#upstream);
it lives in `website/lib/components/upstream_bugs.dart`, so add a new entry in
both places.

[@Komoszek]: https://github.com/Komoszek

[63903]: https://github.com/dart-lang/sdk/issues/63903
[cl-528540]: https://dart-review.googlesource.com/c/sdk/+/528540
[e837b59]: https://github.com/dart-lang/sdk/commit/e837b597586e81afc9a4094f2148fe39e9aa806f

[63944]: https://github.com/dart-lang/sdk/issues/63944
[cl-530160]: https://dart-review.googlesource.com/c/sdk/+/530160
[1cc49b4]: https://github.com/dart-lang/sdk/commit/1cc49b4eeca5c593f970b74bbc1606c318fcaf40

[64422]: https://github.com/dart-lang/sdk/issues/64422
[cl-558400]: https://dart-review.googlesource.com/c/sdk/+/558400
[767a1e2]: https://github.com/dart-lang/sdk/commit/767a1e28c4c15f2dfe860e1e63493e82b0b80dfe

[64629]: https://github.com/dart-lang/sdk/issues/64629
[cl-565940]: https://dart-review.googlesource.com/c/sdk/+/565940
[e7e1ecc]: https://github.com/dart-lang/sdk/commit/e7e1eccd91209ec66656f2a18c60d345fc04af35

[64630]: https://github.com/dart-lang/sdk/issues/64630
[cl-567884]: https://dart-review.googlesource.com/c/sdk/+/567884
[820e2b3]: https://github.com/dart-lang/sdk/commit/820e2b391934edfa55ec17a501e92c7dc2e17f58
