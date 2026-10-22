/// Site-wide constants: where the site lives, where it links to, and how it
/// describes itself to `leancode_jaspr_ds`.
library;

import 'package:ciach_website/components/icons.dart';
import 'package:leancode_jaspr_ds/leancode_jaspr_ds.dart';

/// Public URL of the deployed site. Preview deployments override it with
/// `--dart-define=SITE_URL=https://…` at build time.
const siteUrl = String.fromEnvironment(
  'SITE_URL',
  defaultValue: 'https://ciach.leancode.co',
);

const siteName = 'ciach';
const tagline = 'Dead code detector for Dart and Flutter';
const description =
    'ciach finds declarations nothing references in a Dart or Flutter package '
    '— classes, functions, methods, fields, constants, enum values — and can '
    'remove them for you. Powered by the real Dart analysis server, ready for CI.';

const repoUrl = 'https://github.com/leancodepl/ciach';
const pubUrl = 'https://pub.dev/packages/ciach';
const changelogUrl = '$repoUrl/blob/main/CHANGELOG.md';
const issuesUrl = '$repoUrl/issues';
const readmeUrl = '$repoUrl#readme';

const installCommand = 'dart install ciach';

/// The site as `leancode_jaspr_ds` sees it, at [version].
SiteConfig siteConfig(String version) => .new(
  name: siteName,
  tagline: tagline,
  description: description,
  siteUrl: siteUrl,
  version: version,
  repoUrl: repoUrl,
  pubUrl: pubUrl,
  installCommand: installCommand,
  logo: logo,
  keywords: const [
    'dart',
    'flutter',
    'dead code',
    'unused code',
    'static analysis',
    'cli',
  ],
  alternateName: 'ciach dead code detector',
  runtimePlatform: 'Dart SDK 3.10+',
);

/// The footer of every page.
const siteFooter = SiteFooter(
  ctaHeading: 'Ready to make the first ciach?',
  columns: [
    .new('Project', [
      .new('pub.dev', pubUrl),
      .new('GitHub', repoUrl),
      .new('Changelog', changelogUrl),
      .new('Issues', issuesUrl),
    ]),
    .new('Docs', [
      .new('Install', '/docs#install', external: false),
      .new('CI setup', '/docs#ci', external: false),
      .new('Configuration', '/docs#configuration-file', external: false),
      .new('FAQ', '/docs#faq', external: false),
    ]),
  ],
);
