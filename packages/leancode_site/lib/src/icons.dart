/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// An inline SVG icon of stroked [paths] in a 24-unit box, drawn with Jaspr's
/// typed SVG components so it hydrates cleanly inside client components too.
/// The icons every site uses are the constants here; a site declares its own
/// mark the same way.
class const Icon(
  /// The `d` attributes of the icon's paths.
  final List<String> paths,
) {
  /// How Jaspr passes an icon to a client component: as its paths.
  @decoder
  const new fromJson(List<String> paths) : this(paths);

  static const copy = Icon(['M9 9h10v10H9z', 'M5 15V5h10']);
  static const check = Icon(['m5 12 5 5L20 7']);
  static const link = Icon([
    'M10 14a4 4 0 0 0 5.66 0l3-3a4 4 0 0 0-5.66-5.66l-1.5 1.5',
    'M14 10a4 4 0 0 0-5.66 0l-3 3a4 4 0 0 0 5.66 5.66l1.5-1.5',
  ]);
  static const github = Icon([
    'M12 2a10 10 0 0 0-3.16 19.49c.5.09.68-.22.68-.48v-1.7c-2.78.6-3.37-1.34-3.37-1.34-.45-1.15-1.11-1.46-1.11-1.46-.91-.62.07-.6.07-.6 1 .07 1.53 1.03 1.53 1.03.9 1.53 2.34 1.09 2.91.83.09-.65.35-1.09.63-1.34-2.22-.25-4.55-1.11-4.55-4.94 0-1.09.39-1.98 1.03-2.68-.1-.25-.45-1.27.1-2.64 0 0 .84-.27 2.75 1.02a9.6 9.6 0 0 1 5 0c1.91-1.29 2.75-1.02 2.75-1.02.55 1.37.2 2.39.1 2.64.64.7 1.03 1.59 1.03 2.68 0 3.84-2.34 4.68-4.57 4.93.36.31.68.92.68 1.85v2.74c0 .27.18.58.69.48A10 10 0 0 0 12 2z',
  ]);
  static const arrow = Icon(['M5 12h14', 'm13 6 6 6-6 6']);
  static const external = Icon(['M14 4h6v6', 'M20 4 10 14', 'M18 13v7H4V6h7']);
  static const terminal = Icon(['m4 17 6-6-6-6', 'M12 19h8']);
  static const bolt = Icon(['M13 2 4 14h7l-1 8 9-12h-7z']);
  static const shield = Icon([
    'M12 3 4 6v6c0 5 3.4 8.4 8 9 4.6-.6 8-4 8-9V6z',
    'm9 12 2 2 4-4',
  ]);
  static const git = Icon([
    'M6 3v12',
    'M6 21a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M18 9a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M18 9a9 9 0 0 1-9 9',
  ]);
  static const file = Icon([
    'M14 3H6v18h12V7z',
    'M14 3v4h4',
    'M9 13h6',
    'M9 17h6',
  ]);
  static const layers = Icon([
    'm12 3 9 5-9 5-9-5z',
    'm3 13 9 5 9-5',
    'm3 17 9 5 9-5',
  ]);
  static const gauge = Icon(['M5 19a9 9 0 1 1 14 0', 'M12 13l4-5']);
  static const cog = Icon([
    'M12 15a3 3 0 1 0 0-6 3 3 0 0 0 0 6z',
    'M19 12a7 7 0 0 0-.1-1.2l2-1.5-2-3.5-2.4 1a7 7 0 0 0-2-1.2L14 3h-4l-.5 2.6a7 7 0 0 0-2 1.2l-2.4-1-2 3.5 2 1.5A7 7 0 0 0 5 12a7 7 0 0 0 .1 1.2l-2 1.5 2 3.5 2.4-1a7 7 0 0 0 2 1.2L10 21h4l.5-2.6a7 7 0 0 0 2-1.2l2.4 1 2-3.5-2-1.5A7 7 0 0 0 19 12z',
  ]);
  static const braces = Icon([
    'M8 3H7a2 2 0 0 0-2 2v4a2 2 0 0 1-2 2 2 2 0 0 1 2 2v4a2 2 0 0 0 2 2h1',
    'M16 3h1a2 2 0 0 1 2 2v4a2 2 0 0 0 2 2 2 2 0 0 0-2 2v4a2 2 0 0 1-2 2h-1',
  ]);
  static const book = Icon([
    'M4 4h7v16H4z',
    'M13 4h7v16h-7z',
    'M11 4a2 2 0 0 1 2 0',
  ]);
  static const search = Icon([
    'M11 4a7 7 0 1 0 0 14 7 7 0 0 0 0-14z',
    'm20 20-4-4',
  ]);

  @encoder
  List<String> toJson() => paths;

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
      for (final d in paths) path(attributes: {'d': d}, const []),
    ],
  );
}

/// An SVG favicon: [mark] on a black square, [size] pixels on a side with
/// corners of [radius] in the 64-unit viewBox. A site writes it to
/// `web/favicon.svg` and rasterizes it into the other icons with
/// `package:leancode_site/testing.dart`.
String faviconSvg({
  required String mark,
  required String background,
  int size = 64,
  int radius = 14,
}) =>
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 64 64" '
    'width="$size" height="$size">'
    '<rect width="64" height="64" rx="$radius" fill="$background"/>'
    '$mark</svg>';
