# ciach.leancode.co

The [ciach](https://pub.dev/packages/ciach) landing page, a static
[Jaspr](https://jaspr.site) site.

```bash
dart pub global activate jaspr_cli 0.23.4
dart pub get
jaspr serve
```

`bash tool/build.sh` builds it into `build/jaspr`; Vercel runs the same
script from the GitHub workflows in `.github/workflows/website_*.yml`.
`node tool/render_assets.mjs` regenerates the icons and the social card.

`jaspr_builder` still needs analyzer 12, hence the `dependency_overrides`
and the capped dev dependencies in `pubspec.yaml`.
