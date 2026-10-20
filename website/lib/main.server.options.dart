// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:ciach_website/components/ciach_demo.dart' as _ciach_demo;
import 'package:ciach_website/components/hero.dart' as _hero;
import 'package:ciach_website/components/icons.dart' as _icons;
import 'package:ciach_website/components/upstream_bugs.dart' as _upstream_bugs;
import 'package:ciach_website/content/docs_layout.dart' as _docs_layout;
import 'package:leancode_site/src/components/button.dart' as _button;
import 'package:leancode_site/src/components/card.dart' as _card;
import 'package:leancode_site/src/components/code_block.dart' as _code_block;
import 'package:leancode_site/src/components/copy_button.dart' as _copy_button;
import 'package:leancode_site/src/components/demo_trigger.dart'
    as _demo_trigger;
import 'package:leancode_site/src/components/docs_table.dart' as _docs_table;
import 'package:leancode_site/src/components/docs_toc.dart' as _docs_toc;
import 'package:leancode_site/src/components/faq.dart' as _faq;
import 'package:leancode_site/src/components/feature_grid.dart'
    as _feature_grid;
import 'package:leancode_site/src/components/footer.dart' as _footer;
import 'package:leancode_site/src/components/hero.dart' as _components_hero;
import 'package:leancode_site/src/components/nav_bar.dart' as _nav_bar;
import 'package:leancode_site/src/components/pill.dart' as _pill;
import 'package:leancode_site/src/components/section.dart' as _section;
import 'package:leancode_site/src/components/shell.dart' as _shell;
import 'package:leancode_site/src/components/tabs.dart' as _tabs;
import 'package:leancode_site/src/styles.dart' as _styles;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _copy_button.CopyButton: ClientTarget<_copy_button.CopyButton>(
      'leancode_site:copy_button',
      params: __copy_buttonCopyButton,
    ),
    _demo_trigger.DemoTrigger: ClientTarget<_demo_trigger.DemoTrigger>(
      'leancode_site:demo_trigger',
      params: __demo_triggerDemoTrigger,
    ),
    _docs_toc.DocsToc: ClientTarget<_docs_toc.DocsToc>(
      'leancode_site:docs_toc',
      params: __docs_tocDocsToc,
    ),
  },
  styles: () => [
    ..._styles.styles,
    ..._ciach_demo.CiachDemo.styles,
    ..._hero.Pronunciation.styles,
    ..._icons.Logo.styles,
    ..._upstream_bugs.UpstreamBugs.styles,
    ..._docs_layout.DocsLayout.styles,
    ..._button.Button.styles,
    ..._card.Card.styles,
    ..._code_block.CodeBlock.styles,
    ..._copy_button.CopyButton.styles,
    ..._docs_table.DocsTable.styles,
    ..._faq.Faq.styles,
    ..._feature_grid.FeatureGrid.styles,
    ..._footer.SiteFooter.styles,
    ..._components_hero.Hero.styles,
    ..._nav_bar.NavBar.styles,
    ..._pill.Pill.styles,
    ..._section.DocHeading.styles,
    ..._section.DocSection.styles,
    ..._section.Prose.styles,
    ..._section.Section.styles,
    ..._shell.PageShell.styles,
    ..._tabs.Tabs.styles,
  ],
);

Map<String, Object?> __copy_buttonCopyButton(_copy_button.CopyButton c) => {
  'text': c.text,
  'label': c.label,
  'title': c.title,
  'icon': c.icon.toJson(),
};
Map<String, Object?> __demo_triggerDemoTrigger(_demo_trigger.DemoTrigger c) => {
  'targetId': c.targetId,
};
Map<String, Object?> __docs_tocDocsToc(_docs_toc.DocsToc c) => {
  'path': c.path,
  'ids': c.ids,
  'labels': c.labels,
};
