# ciach landing page

The [ciach](https://pub.dev/packages/ciach) website at
[ciach.leancode.co](https://ciach.leancode.co), built with
[Jaspr](https://jaspr.site) in static mode: every component renders to plain
HTML at build time, and only the copy-to-clipboard buttons hydrate on the client.

## Develop

```bash
dart pub global activate jaspr_cli 0.23.4
cd website
dart pub get
jaspr serve          # http://localhost:8080, hot-reloads on save
```

## Build

```bash
jaspr build --sitemap-domain https://ciach.leancode.co \
  --dart-define=SITE_URL=https://ciach.leancode.co
```

The static site lands in `build/jaspr/`. `SITE_URL` drives the `<base href>`,
the canonical URL, Open Graph URLs and the JSON-LD; it defaults to the
production domain, so the define only matters for previews. `--sitemap-domain`
generates `sitemap.xml` for the same domain.

## Deploy

The site is hosted on Vercel. `vercel.json` in this directory holds the whole
build configuration, so the Vercel project only needs:

- **Root Directory**: `website`
- **Framework Preset**: Other
- **Domain**: `ciach.leancode.co`

`tool/vercel_install.sh` downloads a pinned Dart SDK into `.dart-sdk/` (the
Vercel image has none) and activates the Jaspr CLI; `tool/vercel_build.sh`
runs `jaspr build` and trims build_runner's intermediate output. Production
builds advertise `https://ciach.leancode.co`; preview builds use their
`VERCEL_URL` and ship a `robots.txt` that disallows indexing.

`.github/workflows/website.yml` analyzes, format-checks and builds the site on
pull requests and pushes to `main`, so a broken site fails the check before
Vercel ever sees it.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/main.server.dart` | Entry point; wires the `Document` (title, meta, head) and reads the ciach version from the package's `pubspec.yaml`. |
| `lib/seo.dart` | Canonical link, icons, Open Graph and Twitter cards, JSON-LD (`SoftwareSourceCode`, `WebSite`, `FAQPage`). |
| `lib/highlight.dart` | Build-time syntax highlighting: `syntax_highlight_lite` (the TextMate engine behind `jaspr_content`) plus a scope-to-CSS-class mapping and per-line splitting. |
| `lib/grammars/` | TextMate grammars: JSON and YAML vendored from `syntax_highlight`, plus small ones for shell prompts and ciach's own terminal output. |
| `lib/components/` | One file per page section, plus `CodeBlock`, `Terminal` and the `@client` `CopyButton`. |
| `web/styles.css` | The stylesheet. Design tokens are CSS custom properties at the top. |
| `web/` | Static assets copied verbatim: favicon, manifest, robots.txt, the Open Graph image. |

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
