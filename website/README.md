# ciach landing page

The [ciach](https://pub.dev/packages/ciach) website at
[ciach.leancode.co](https://ciach.leancode.co), built with
[Jaspr](https://jaspr.site) in static mode: every component renders to plain
HTML at build time, and only three small islands hydrate on the client: the
copy-to-clipboard buttons, the scroll-following docs table of contents and the
trigger that starts the `--remove` animation.

## Develop

```bash
dart pub global activate jaspr_cli 0.23.4
cd website
dart pub get
jaspr serve          # http://localhost:8080, hot-reloads on save
```

## Build

```bash
SITE_URL=https://ciach.leancode.co bash tool/build.sh
```

The static site lands in `build/jaspr/`. `SITE_URL` drives the `<base href>`,
the canonical URL, Open Graph URLs, the JSON-LD and the sitemap; it defaults
to the production domain, and any other value produces a preview build whose
`robots.txt` disallows indexing.

## Deploy

The site is hosted on Vercel as the `ciach` project of the `leancode`
team and deployed from GitHub Actions with the Vercel CLI, the same way as
[flitz-landing](https://github.com/leancodepl/flitz-landing): `vercel pull`,
`vercel build`, `vercel deploy --prebuilt`.

- `.github/workflows/website_production.yml` runs on pushes to `main` that
  touch `website/` or the package version, deploys to production and aliases
  the deployment to `ciach.leancode.co`.
- `.github/workflows/website_preview.yml` runs on pull requests that touch
  `website/`: analyzer, formatter, then a preview deployment aliased to
  `ciach-<branch>.vercel.app` and built for that URL.

The only secret is `VERCEL_TOKEN`. Both workflows create the Vercel project
if it does not exist yet and link it with `vercel link`, so no org or project
id secrets are needed. `vercel.json` in this directory holds the build
configuration the CLI uses (`tool/build.sh`, output in `build/jaspr`, cache
headers); Dart comes from `dart-lang/setup-dart` in the workflow.

One-time DNS: `ciach.leancode.co` needs a CNAME to `cname.vercel-dns.com`
(or the record Vercel shows for the domain in the project settings). The
production workflow's alias step assigns the domain to the project.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/main.server.dart` | Entry point; wires the `Document` (title, meta, head) and reads the ciach version from the package's `pubspec.yaml`. |
| `lib/seo.dart` | Canonical link, icons, Open Graph and Twitter cards, JSON-LD (`SoftwareSourceCode`, `WebSite`, `FAQPage`). |
| `lib/highlight.dart` | Build-time syntax highlighting: `syntax_highlight_lite` (the TextMate engine behind `jaspr_content`) plus a scope-to-CSS-class mapping and per-line splitting. |
| `lib/grammars/` | TextMate grammars: JSON and YAML vendored from `syntax_highlight`, plus small ones for shell prompts and ciach's own terminal output. |
| `lib/app.dart` | The `jaspr_router` routes: `/` (landing page) and `/docs`. |
| `lib/pages/` | The two pages; each sets its own title, description and canonical URL through `pageHead`. |
| `lib/components/` | Sections and building blocks: `CodeBlock`, `Terminal`, the page shell, and the three `@client` islands: `CopyButton`, `DocsToc` and `DemoTrigger`. |
| `web/styles.css` | The stylesheet. Design tokens are CSS custom properties at the top. |
| `web/` | Static assets copied verbatim: favicon, manifest, robots.txt, the Open Graph image. |
| `tool/render_assets.mjs` | Regenerates the PNG icons and the Open Graph image from `favicon.svg` with Playwright: `PLAYWRIGHT_CHROMIUM=<path> node tool/render_assets.mjs` (needs `playwright` resolvable from `tool/`). |

## Notes

- `jaspr_builder` 0.23 requires `analyzer` 12 and does not compile against
  13 or 14. `leancode_lint` requires 13+, but only its `analysis_options.yaml`
  is consumed here (an enabled plugin is resolved separately by the analysis
  server under `~/.dartServer/.plugin_manager/`), so `dependency_overrides`
  pins `analyzer` to 12. That override hides other packages' analyzer
  requirements from pub, so `build_runner`, `build_web_compilers` and
  `dart_style` are capped at their last analyzer-12 releases and
  `pubspec.lock` is committed; a fresh resolve without those would pick
  versions that fail to compile. Three lint rules whose fixes produce Dart 3.13 constructor syntax are off,
  since analyzer 12 cannot parse it. Drop all of this once Jaspr moves to a
  newer analyzer.
- The package is excluded from the root `dart analyze` (see the root
  `analysis_options.yaml`) and from the published package (`.pubignore`).
