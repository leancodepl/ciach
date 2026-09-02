import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// Inline SVG icons, drawn with Jaspr's typed SVG components so they hydrate
/// cleanly inside client components too.
enum Icon {
  copy(['M9 9h10v10H9z', 'M5 15V5h10']),
  check(['m5 12 5 5L20 7']),
  github([
    'M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.15-1.11-1.46-1.11-1.46-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2z',
  ]),
  arrow(['M5 12h14', 'm13 6 6 6-6 6']),
  external(['M14 4h6v6', 'M20 4 10 14', 'M18 13v7H4V6h7']),
  terminal(['m4 17 6-6-6-6', 'M12 19h8']),
  knife([
    'M3 21 14.5 9.5',
    'M14.5 9.5 21 3c-1.5 5.5-4 8.5-8 10.5',
    'M9 15 5.5 18.5',
  ]),
  bolt(['M13 2 4 14h7l-1 8 9-12h-7z']),
  shield(['M12 3 4 6v6c0 5 3.4 8.4 8 9 4.6-.6 8-4 8-9V6z', 'm9 12 2 2 4-4']),
  git([
    'M6 3v12',
    'M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M18 9a9 9 0 0 1-9 9',
  ]),
  file(['M14 3H6v18h12V7z', 'M14 3v4h4', 'M9 13h6', 'M9 17h6']),
  layers(['m12 3 9 5-9 5-9-5z', 'm3 13 9 5 9-5', 'm3 17 9 5 9-5']),
  gauge(['M5 19a9 9 0 1 1 14 0', 'M12 13l4-5']),
  cog([
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.5-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.5 2 1.5A7 7 0 0 0 5 12a7 7 0 0 0 .1 1.2l-2 1.5 2 3.5 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.5-2-1.5A7 7 0 0 0 19 12z',
  ]),
  braces([
    'M8 3H7a2 2 0 0 0-2 2v4a2 2 0 0 1-2 2 2 2 0 0 1 2 2v4a2 2 0 0 0 2 2h1',
    'M16 3h1a2 2 0 0 1 2 2v4a2 2 0 0 0 2 2 2 2 0 0 0-2 2v4a2 2 0 0 1-2 2h-1',
  ]),
  book(['M4 4h7v16H4z', 'M13 4h7v16h-7z', 'M11 4a2 2 0 0 1 2 0']),
  search(['M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z', 'm20 20-4-4']);

  const Icon(this.paths);

  final List<String> paths;

  Component build({int size = 20, String? classes}) => svg(
    classes: classes,
    attributes: {
      'viewBox': '0 0 24 24',
      'width': '$size',
      'height': '$size',
      'fill': 'none',
      'stroke': 'currentColor',
      'stroke-width': '1.75',
      'stroke-linecap': 'round',
      'stroke-linejoin': 'round',
      'aria-hidden': 'true',
      'focusable': 'false',
    },
    [
      for (final d in paths) path(const [], attributes: {'d': d}),
    ],
  );
}

/// The ciach word mark: a chopped-off "ciach" with an accent slash.
Component logo({bool large = false}) => span(
  classes: large ? 'logo logo-large' : 'logo',
  attributes: const {'aria-hidden': 'true'},
  [
    span(classes: 'logo-mark', [Icon.knife.build(size: large ? 28 : 20)]),
    const span(classes: 'logo-text', [Component.text('ciach')]),
  ],
);
