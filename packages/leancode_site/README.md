<!--
AI-Provenance:
  model: claude-fable-5-1
  harness: Claude Code
-->

# leancode_site

The LeanCode design system for the Jaspr sites of LeanCode's packages: the
palette and tokens, the base styles, the fonts, the shared components, and the
plumbing a package landing page needs. [ciach.leancode.co](../../website) is
built on it and is the reference for every step below.

## Depending on the package

The package uses Jaspr from a commit on its `next` branch, whose builder
parses the primary constructors the package is written with. A site depends
on the package from git and overrides jaspr to the same commit, which
`dependency_overrides` in this package's `pubspec.yaml` names:

```yaml
dependencies:
  jaspr: ^0.23.4
  jaspr_class_scope: ^0.1.1
  leancode_site:
    git:
      url: https://github.com/leancodepl/ciach
      path: packages/leancode_site
      ref: <commit>

dev_dependencies:
  build_runner: ^2.10.0
  build_web_compilers: ^4.8.5
  jaspr_builder: ^0.23.4
  jaspr_class_scope_builder: ^0.1.0

dependency_overrides:
  jaspr:
    git:
      url: https://github.com/schultek/jaspr
      path: packages/jaspr
      ref: <the commit from this package's pubspec.yaml>
  jaspr_builder:
    git:
      url: https://github.com/schultek/jaspr
      path: packages/jaspr_builder
      ref: <the same commit>
```

The Jaspr CLI comes from the same commit:

```bash
dart pub global activate --source git https://github.com/schultek/jaspr --git-path packages/jaspr_cli --git-ref <the same commit>
```

A site in this repository depends on the package by path instead. Either way,
Jaspr collects the package's `@css` styles and `@client` islands into the
site's generated options on its own; nothing is registered by hand.

## Building a site on it

1. **Describe the site** in a `SiteConfig`: name, tagline, description, URLs,
   install command, version, keywords and logo. Read the version with
   `versionFromPubspec` from `package:leancode_site/server.dart`.
2. **Wrap the `Document`** in a `Site` with that config, give the document
   `base: config.basePath` and `meta: siteMeta(config)`, and put `SiteHead()`
   in its head. Every shared component reads the config through `Site.of`.
3. **Register the highlighter** before rendering with `initHighlighting`,
   passing the site's own `Language`s, such as the output of its program
   with a TextMate grammar that includes `kShellPatterns` for prompt lines.
4. **Build pages** from `PageShell`, which takes the page's path and the
   site's `SiteFooter`, and inside it `PageHead` and the components: `Hero`,
   `Section`, `FeatureGrid`, `Tabs`, `CodeBlock`, `Terminal`, `Faq`,
   `DocSection`, `DocsToc`, `Card`, `Pill`, `Button`. The site adds its own
   components next to them, styled with the same tokens from `styles.dart`
   and the `Palette`.
5. **Bring the mark**: an `Icon` for the word mark that `SiteConfig.logo`
   draws, and a favicon from `faviconSvg`.
6. **Keep the fonts in the build.** They are served from
   `packages/leancode_site/fonts/`, so the build script keeps that directory
   of the build output and removes the rest of `packages/`, as
   `website/tool/build.sh` does.
7. **Check the assets** with `assetGoldenTests` from
   `package:leancode_site/testing.dart`: it renders the favicon set with
   `iconAssets`, the social card with `ogCardAsset`, writes `favicon.svg` and
   `webManifest`, and compares them all with the committed files.
   `UPDATE_GOLDENS=1 dart test` rewrites them.

## What is in the package

| Library | What is in it |
| --- | --- |
| `leancode_site.dart` | `Palette`, the tokens and base styles, the fonts, the components, `SiteConfig` and `Site`, `SiteHead` and `PageHead`, the highlighter and `Icon`. |
| `server.dart` | `versionFromPubspec`, for the server entrypoint. |
| `testing.dart` | `assetGoldenTests`, `iconAssets`, `ogCardAsset`, `AssetRenderer` and `compare`. |

The colors are the design system's, under its names, in `Palette`. The
fonts are Space Grotesk and JetBrains Mono, self-hosted under the SIL Open
Font License.

## Working on the package

The `.scopes.dart` part files are generated and committed; after adding,
renaming or moving a component, run `dart run build_runner build` here.
`dart test` runs the package's own tests; the site's asset test covers the
rendered result.

## Not covered yet

- The navigation has the three links every site shares: the docs, pub.dev
  and GitHub. A site that needs more items, such as a theme toggle, needs a
  slot added here.
- There is no light theme; the design system allows one.
- The design system's callout bar, marker, stat card, media frame, link row
  and square-bullet list have no component yet.
