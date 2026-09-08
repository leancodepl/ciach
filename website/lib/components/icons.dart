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

  Icon(this.paths);

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
      for (final d in paths) path(attributes: {'d': d}, const []),
    ],
  );
}

/// The ciach logo: the blade on its tile next to the word mark.
///
/// The word mark is the package name set in Space Grotesk Bold and outlined,
/// then cut along a line 30° off vertical through the "a", with the two halves
/// pushed apart and the right one dropped a little along the cut. The design
/// lives in `design/logo/`. The halves are clipped with `<clipPath>`s, which
/// need document-unique ids, so a page showing the logo twice passes a
/// different [id] each time.
Component logo({bool large = false, String id = 'logo'}) => span(
  classes: large ? 'logo logo-large' : 'logo',
  attributes: const {'aria-hidden': 'true'},
  [
    span(classes: 'logo-mark', [logoMark(size: large ? 30 : 22)]),
    span(classes: 'logo-text', [wordMark(id: id)]),
  ],
);

/// The knife: a pictogram of a deep blade and a stub handle with a gap between
/// them, on the 24-unit icon grid, pointing up-right along the 30° cut of the
/// word mark. A single filled path, unlike the stroked [Icon]s, so it draws
/// the same in the site header, the favicon and the social card.
/// `web/favicon.svg` carries the same path.
Component logoMark({int size = 24}) => svg(
  attributes: {
    'viewBox': '0 0 24 24',
    'width': '$size',
    'height': '$size',
    'fill': 'currentColor',
    'aria-hidden': 'true',
    'focusable': 'false',
  },
  const [
    path(attributes: {'d': _logoMarkPath}, []),
  ],
);

const _logoMarkPath =
    'M6.05 17.11L6.75 15.9Q8.05 13.64 10.3 14.94L10.3 14.94Q12.55 16.24 11.25 18.5L10.55 19.71Q9.25 21.96 7 20.66L7 20.66Q4.75 19.36 6.05 17.11ZM8.6 12.69L17 3.34C16.76 9.16 18.81 12.2 16.05 16.99Z';

/// The cut "ciach" word mark as an inline SVG, filled with `currentColor` and
/// sized by the surrounding font size (see `.logo-text svg` in `NavBar`).
Component wordMark({required String id}) {
  // One half of the word mark: the letters clipped to one side of the cut,
  // then moved away from it.
  Component half(String side, String shift) => Component.element(
    tag: 'g',
    attributes: {'transform': shift, 'clip-path': 'url(#$id-$side)'},
    children: [
      for (final d in _wordMarkPaths) path(attributes: {'d': d}, const []),
    ],
  );
  Component clip(String side, String points) => Component.element(
    tag: 'clipPath',
    id: '$id-$side',
    children: [polygon(points: points, const [])],
  );
  return svg(
    attributes: const {
      'viewBox': '-4 -4 309.18 95.36',
      'fill': 'currentColor',
      'aria-hidden': 'true',
      'focusable': 'false',
    },
    [
      Component.element(
        tag: 'defs',
        children: [
          clip('left', '180.31,-40 -40,-40 -40,127.36 83.69,127.36'),
          clip('right', '180.31,-40 341.18,-40 341.18,127.36 83.69,127.36'),
        ],
      ),
      half('left', 'translate(-1.6 -3.23)'),
      half('right', 'translate(1.6 3.23)'),
    ],
  );
}

/// The letters c, i, a, c, h of the word mark, in a 301.18×87.36 box.
const _wordMarkPaths = [
  'M 30.84 87.36 C 25.08 87.36 19.84 86.16 15.12 83.76 C 10.48 81.36 6.8 77.88 4.08 73.32 C 1.36 68.76 0 63.24 0 56.76 L 0 55.08 C 0 48.6 1.36 43.08 4.08 38.52 C 6.8 33.96 10.48 30.48 15.12 28.08 C 19.84 25.68 25.08 24.48 30.84 24.48 C 36.52 24.48 41.4 25.48 45.48 27.48 C 49.56 29.48 52.84 32.24 55.32 35.76 C 57.88 39.2 59.56 43.12 60.36 47.52 L 45.72 50.64 C 45.4 48.24 44.68 46.08 43.56 44.16 C 42.44 42.24 40.84 40.72 38.76 39.6 C 36.76 38.48 34.24 37.92 31.2 37.92 C 28.16 37.92 25.4 38.6 22.92 39.96 C 20.52 41.24 18.6 43.2 17.16 45.84 C 15.8 48.4 15.12 51.56 15.12 55.32 L 15.12 56.52 C 15.12 60.28 15.8 63.48 17.16 66.12 C 18.6 68.68 20.52 70.64 22.92 72 C 25.4 73.28 28.16 73.92 31.2 73.92 C 35.76 73.92 39.2 72.76 41.52 70.44 C 43.92 68.04 45.44 64.92 46.08 61.08 L 60.72 64.56 C 59.68 68.8 57.88 72.68 55.32 76.2 C 52.84 79.64 49.56 82.36 45.48 84.36 C 41.4 86.36 36.52 87.36 30.84 87.36 Z',
  'M 73.19 85.68 L 73.19 26.16 L 88.31 26.16 L 88.31 85.68 L 73.19 85.68 Z M 80.75 19.2 C 78.03 19.2 75.71 18.32 73.79 16.56 C 71.95 14.8 71.03 12.48 71.03 9.6 C 71.03 6.72 71.95 4.4 73.79 2.64 C 75.71 0.88 78.03 0 80.75 0 C 83.55 0 85.87 0.88 87.71 2.64 C 89.55 4.4 90.47 6.72 90.47 9.6 C 90.47 12.48 89.55 14.8 87.71 16.56 C 85.87 18.32 83.55 19.2 80.75 19.2 Z',
  'M 123.55 87.36 C 119.31 87.36 115.51 86.64 112.15 85.2 C 108.79 83.68 106.11 81.52 104.11 78.72 C 102.19 75.84 101.23 72.36 101.23 68.28 C 101.23 64.2 102.19 60.8 104.11 58.08 C 106.11 55.28 108.83 53.2 112.27 51.84 C 115.79 50.4 119.79 49.68 124.27 49.68 L 140.59 49.68 L 140.59 46.32 C 140.59 43.52 139.71 41.24 137.95 39.48 C 136.19 37.64 133.39 36.72 129.55 36.72 C 125.79 36.72 122.99 37.6 121.15 39.36 C 119.31 41.04 118.11 43.24 117.55 45.96 L 103.63 41.28 C 104.59 38.24 106.11 35.48 108.19 33 C 110.35 30.44 113.19 28.4 116.71 26.88 C 120.31 25.28 124.67 24.48 129.79 24.48 C 137.63 24.48 143.83 26.44 148.39 30.36 C 152.95 34.28 155.23 39.96 155.23 47.4 L 155.23 69.6 C 155.23 72 156.35 73.2 158.59 73.2 L 163.39 73.2 L 163.39 85.68 L 153.31 85.68 C 150.35 85.68 147.91 84.96 145.99 83.52 C 144.07 82.08 143.11 80.16 143.11 77.76 L 143.11 77.64 L 140.83 77.64 C 140.51 78.6 139.79 79.88 138.67 81.48 C 137.55 83 135.79 84.36 133.39 85.56 C 130.99 86.76 127.71 87.36 123.55 87.36 Z M 126.19 75.12 C 130.43 75.12 133.87 73.96 136.51 71.64 C 139.23 69.24 140.59 66.08 140.59 62.16 L 140.59 60.96 L 125.35 60.96 C 122.55 60.96 120.35 61.56 118.75 62.76 C 117.15 63.96 116.35 65.64 116.35 67.8 C 116.35 69.96 117.19 71.72 118.87 73.08 C 120.55 74.44 122.99 75.12 126.19 75.12 Z',
  'M 201.23 87.36 C 195.47 87.36 190.23 86.16 185.51 83.76 C 180.87 81.36 177.19 77.88 174.47 73.32 C 171.75 68.76 170.39 63.24 170.39 56.76 L 170.39 55.08 C 170.39 48.6 171.75 43.08 174.47 38.52 C 177.19 33.96 180.87 30.48 185.51 28.08 C 190.23 25.68 195.47 24.48 201.23 24.48 C 206.91 24.48 211.79 25.48 215.87 27.48 C 219.95 29.48 223.23 32.24 225.71 35.76 C 228.27 39.2 229.95 43.12 230.75 47.52 L 216.11 50.64 C 215.79 48.24 215.07 46.08 213.95 44.16 C 212.83 42.24 211.23 40.72 209.15 39.6 C 207.15 38.48 204.63 37.92 201.59 37.92 C 198.55 37.92 195.79 38.6 193.31 39.96 C 190.91 41.24 188.99 43.2 187.55 45.84 C 186.19 48.4 185.51 51.56 185.51 55.32 L 185.51 56.52 C 185.51 60.28 186.19 63.48 187.55 66.12 C 188.99 68.68 190.91 70.64 193.31 72 C 195.79 73.28 198.55 73.92 201.59 73.92 C 206.15 73.92 209.59 72.76 211.91 70.44 C 214.31 68.04 215.83 64.92 216.47 61.08 L 231.11 64.56 C 230.07 68.8 228.27 72.68 225.71 76.2 C 223.23 79.64 219.95 82.36 215.87 84.36 C 211.79 86.36 206.91 87.36 201.23 87.36 Z',
  'M 243.58 85.68 L 243.58 1.68 L 258.7 1.68 L 258.7 33.48 L 260.86 33.48 C 261.5 32.2 262.5 30.92 263.86 29.64 C 265.22 28.36 267.02 27.32 269.26 26.52 C 271.58 25.64 274.5 25.2 278.02 25.2 C 282.66 25.2 286.7 26.28 290.14 28.44 C 293.66 30.52 296.38 33.44 298.3 37.2 C 300.22 40.88 301.18 45.2 301.18 50.16 L 301.18 85.68 L 286.06 85.68 L 286.06 51.36 C 286.06 46.88 284.94 43.52 282.7 41.28 C 280.54 39.04 277.42 37.92 273.34 37.92 C 268.7 37.92 265.1 39.48 262.54 42.6 C 259.98 45.64 258.7 49.92 258.7 55.44 L 258.7 85.68 L 243.58 85.68 Z',
];
