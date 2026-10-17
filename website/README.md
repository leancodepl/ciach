# ciach.leancode.co

The [ciach](https://pub.dev/packages/ciach) landing page, a static
[Jaspr](https://jaspr.site) site. It uses Jaspr from the commit on the `next`
branch that `dependency_overrides` in `pubspec.yaml` names. Activate the Jaspr
CLI from the same commit with the `dart pub global activate` command in the
`installCommand` of `vercel.json`, then run:

```bash
dart pub get
jaspr serve
```

`bash tool/build.sh` builds it into `build/jaspr`; Vercel runs the same
script from the GitHub workflows in `.github/workflows/website_*.yml`.
`dart test` renders the icons and the social card again, regenerates
`favicon.svg` and the web manifest, and compares them all with the committed
files (CI does this on every pull request); `UPDATE_GOLDENS=1 dart test`
rewrites them after an intended change. Colors live in `lib/palette.dart`.

Each component's class names are scoped to it with
[jaspr_class_scope](https://pub.dev/packages/jaspr_class_scope): a component
declares them as `_class('name')` and renders them with a suffix of its own.
The `.scopes.dart` part files holding those suffixes are generated and
committed; `jaspr serve` and `jaspr build` rewrite them, and so does
`dart run build_runner build`, after a component is added, renamed or moved.
