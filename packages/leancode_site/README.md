<!--
AI-Provenance:
  model: claude-fable-5-1
  harness: Claude Code
-->

# leancode_site

The LeanCode design system for the Jaspr sites of LeanCode's packages: the
palette and tokens, the base styles, the fonts, the shared components, and the
plumbing a package landing page needs. [ciach.leancode.co](../../website)
is built on it.

## What a site brings

- A `SiteConfig`: the name, tagline, description, URLs, install command,
  version and logo. Every shared component reads it through `Site.of`, so a
  site wraps its `Document` in a `Site`.
- Its own pages, assembled from `PageShell`, `Hero`, `Section`, `FeatureGrid`,
  `Tabs`, `CodeBlock`, `Terminal`, `Faq` and the rest of the components, plus
  the components only it needs.
- Its mark: an `Icon` for the word mark and `faviconSvg` for the icons.
- Its own console `Language`, when it shows the output of its program.

## What the package brings

| Library | What is in it |
| --- | --- |
| `leancode_site.dart` | `Palette`, the tokens and base styles, the fonts, the components, `SiteConfig`, `SiteHead`, `PageHead`, the highlighter. |
| `server.dart` | `versionFromPubspec`, for the server entrypoint. |
| `testing.dart` | `assetGoldenTests`, which renders a site's icons and social card and compares them with the committed files. |

The fonts are served from `packages/leancode_site/fonts/`, so a site's build
keeps that directory of the build output.

## Working on the package

Jaspr collects the `@css` styles and `@client` islands of a dependency on its
own, so a site needs no registration step. The `.scopes.dart` part files are
generated and committed; after adding, renaming or moving a component, run
`dart run build_runner build` here.

Sites that pin the published jaspr 0.23 build parse with analyzer 12, which
has no primary constructors, so the package keeps classic constructors until
jaspr publishes a builder for analyzer 13.
