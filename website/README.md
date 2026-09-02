# ciach landing page

The [ciach](https://pub.dev/packages/ciach) website, built with
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
jaspr build --sitemap-domain https://leancodepl.github.io/ciach \
  --dart-define=SITE_URL=https://leancodepl.github.io/ciach
```

The static site lands in `build/jaspr/`. `SITE_URL` drives the `<base href>`,
the canonical URL, Open Graph URLs and the JSON-LD, so pass the URL the site
will actually be served from; `--sitemap-domain` generates `sitemap.xml` for
the same domain.

## Deploy

`.github/workflows/website.yml` builds the site on every push to `main` that
touches `website/` and publishes it to GitHub Pages. It also builds (without
deploying) on pull requests, so a broken site fails the check.

The workflow reads the Pages URL from `actions/configure-pages`, so switching to
a custom domain only needs the domain configured in the repository's Pages
settings.

## Layout

| Path | What lives there |
| --- | --- |
| `lib/main.server.dart` | Entry point; wires the `Document` (title, meta, head) and reads the ciach version from the package's `pubspec.yaml`. |
| `lib/seo.dart` | Canonical link, icons, Open Graph and Twitter cards, JSON-LD (`SoftwareSourceCode`, `WebSite`, `FAQPage`). |
| `lib/highlight.dart` | Build-time syntax highlighter for the Dart, YAML, shell, JSON and ciach-output samples. |
| `lib/components/` | One file per page section, plus `CodeBlock`, `Terminal` and the `@client` `CopyButton`. |
| `web/styles.css` | The stylesheet. Design tokens are CSS custom properties at the top. |
| `web/` | Static assets copied verbatim: favicon, manifest, robots.txt, the Open Graph image. |

## Notes

- `build_web_compilers` is capped below 4.8.6 because `jaspr_builder` 0.23
  still pins `analyzer` 12. The same conflict keeps `leancode_lint` out of this
  package for now; it uses `package:lints` instead.
- The package is excluded from the root `dart analyze` (see the root
  `analysis_options.yaml`) and from the published package (`.pubignore`).
