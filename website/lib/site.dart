/// Site-wide constants: where the site lives and where it links to.
library;

/// Public URL of the deployed site. Preview deployments override it with
/// `--dart-define=SITE_URL=https://…` at build time.
const siteUrl = String.fromEnvironment(
  'SITE_URL',
  defaultValue: 'https://ciach.leancode.co',
);

/// [siteUrl] with a guaranteed trailing slash, for canonical and Open Graph
/// URLs.
final canonicalUrl = siteUrl.endsWith('/') ? siteUrl : '$siteUrl/';

/// The `<base href>` derived from [siteUrl], so relative asset paths still
/// resolve if the site is ever served from a sub-path.
final basePath = () {
  final path = Uri.parse(siteUrl).path;
  if (path.isEmpty || path == '/') {
    return '/';
  }
  return path.endsWith('/') ? path : '$path/';
}();

const siteName = 'ciach';
const tagline = 'Dead code detector for Dart and Flutter';
const description =
    'ciach finds declarations nothing references in a Dart or Flutter package '
    '— classes, functions, methods, fields, constants, enum values — and can '
    'remove them for you. Powered by the real Dart analysis server, ready for CI.';

const repoUrl = 'https://github.com/leancodepl/ciach';
const pubUrl = 'https://pub.dev/packages/ciach';
const pubScoreUrl = 'https://pub.dev/packages/ciach/score';
const changelogUrl = '$repoUrl/blob/main/CHANGELOG.md';
const issuesUrl = '$repoUrl/issues';
const licenseUrl = '$repoUrl/blob/main/LICENSE';
const readmeUrl = '$repoUrl#readme';
const exampleUrl = '$repoUrl/tree/main/example';

const _utm = 'utm_source=ciach-website&utm_medium=referral&utm_campaign=ciach';
const leancodeUrl = 'https://leancode.co/?$_utm';
const leancodeEstimateUrl = 'https://leancode.co/get-estimate?$_utm';
const leancodePackagesUrl =
    'https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads';
const patrolUrl = 'https://patrol.leancode.co/?$_utm';

const installCommand = 'dart pub global activate ciach';
const devDependencyCommand = 'dart pub add --dev ciach';
