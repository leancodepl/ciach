/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

/// The LeanCode design system for Jaspr sites: the palette and tokens, the
/// base styles, the shared components and the plumbing a package landing page
/// needs. A site describes itself in a `SiteConfig`, wraps its `Document` in
/// a `Site`, and builds its pages from the components here and its own.
library;

export 'src/components/button.dart';
export 'src/components/card.dart';
export 'src/components/code_block.dart';
export 'src/components/copy_button.dart';
export 'src/components/demo_trigger.dart';
export 'src/components/docs_table.dart';
export 'src/components/docs_toc.dart';
export 'src/components/faq.dart';
export 'src/components/feature_grid.dart';
export 'src/components/footer.dart';
export 'src/components/hero.dart';
export 'src/components/nav_bar.dart';
export 'src/components/og_card.dart';
export 'src/components/pill.dart';
export 'src/components/section.dart';
export 'src/components/shell.dart';
export 'src/components/tabs.dart';
export 'src/fonts.dart';
export 'src/highlight/grammars/shell_grammar.dart' show kShellPatterns;
export 'src/highlight/highlight.dart';
export 'src/icons.dart';
export 'src/palette.dart';
export 'src/seo.dart';
export 'src/site_config.dart';
export 'src/styles.dart';
