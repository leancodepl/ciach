// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:ciach_website/components/button.dart' as _button;
import 'package:ciach_website/components/card.dart' as _card;
import 'package:ciach_website/components/ciach_demo.dart' as _ciach_demo;
import 'package:ciach_website/components/code_block.dart' as _code_block;
import 'package:ciach_website/components/copy_button.dart' as _copy_button;
import 'package:ciach_website/components/demo_trigger.dart' as _demo_trigger;
import 'package:ciach_website/components/docs_toc.dart' as _docs_toc;
import 'package:ciach_website/components/faq.dart' as _faq;
import 'package:ciach_website/components/features.dart' as _features;
import 'package:ciach_website/components/footer.dart' as _footer;
import 'package:ciach_website/components/formats.dart' as _formats;
import 'package:ciach_website/components/hero.dart' as _hero;
import 'package:ciach_website/components/nav_bar.dart' as _nav_bar;
import 'package:ciach_website/components/pill.dart' as _pill;
import 'package:ciach_website/components/section.dart' as _section;
import 'package:ciach_website/pages/docs_page.dart' as _docs_page;
import 'package:ciach_website/styles.dart' as _styles;

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
      'copy_button',
      params: __copy_buttonCopyButton,
    ),
    _demo_trigger.DemoTrigger: ClientTarget<_demo_trigger.DemoTrigger>(
      'demo_trigger',
      params: __demo_triggerDemoTrigger,
    ),
    _docs_toc.DocsToc: ClientTarget<_docs_toc.DocsToc>(
      'docs_toc',
      params: __docs_tocDocsToc,
    ),
  },
  styles: () => [
    ..._styles.styles,
    ..._button.Button.styles,
    ..._card.Card.styles,
    ..._ciach_demo.CiachDemo.styles,
    ..._code_block.CodeBlock.styles,
    ..._copy_button.CopyButton.styles,
    ..._faq.Faq.styles,
    ..._features.Features.styles,
    ..._footer.SiteFooter.styles,
    ..._formats.OutputFormats.styles,
    ..._hero.Hero.styles,
    ..._nav_bar.NavBar.styles,
    ..._pill.Pill.styles,
    ..._section.Section.styles,
    ..._docs_page.DocsPage.styles,
  ],
);

Map<String, Object?> __copy_buttonCopyButton(_copy_button.CopyButton c) => {
  'text': c.text,
  'label': c.label,
};
Map<String, Object?> __demo_triggerDemoTrigger(_demo_trigger.DemoTrigger c) => {
  'targetId': c.targetId,
};
Map<String, Object?> __docs_tocDocsToc(_docs_toc.DocsToc c) => {
  'path': c.path,
  'ids': c.ids,
  'labels': c.labels,
};
