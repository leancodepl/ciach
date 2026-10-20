/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:jaspr/dom.dart';
import 'package:leancode_site/leancode_site.dart';
import 'package:test/test.dart';

SiteConfig _config(String siteUrl) => .new(
  name: 'sample',
  tagline: 'A sample package',
  description: 'Does sample things.',
  siteUrl: siteUrl,
  version: '1.2.3',
  repoUrl: 'https://github.com/leancodepl/sample',
  pubUrl: 'https://pub.dev/packages/sample',
  installCommand: 'dart pub add sample',
  logo: ({large = false}) => const span([]),
  keywords: const ['dart'],
);

void main() {
  group('SiteConfig', () {
    test('`canonicalUrl` ends with a slash whether or not `siteUrl` does', () {
      expect(
        _config('https://sample.leancode.co').canonicalUrl,
        'https://sample.leancode.co/',
      );
      expect(
        _config('https://sample.leancode.co/').canonicalUrl,
        'https://sample.leancode.co/',
      );
    });

    test('`basePath` is `/` for a site at the root of its domain', () {
      expect(_config('https://sample.leancode.co').basePath, '/');
      expect(_config('https://sample.leancode.co/').basePath, '/');
    });

    test(
      '`basePath` is the sub-path with a trailing slash for a site under one',
      () {
        expect(_config('https://leancode.co/sample').basePath, '/sample/');
        expect(_config('https://leancode.co/sample/').basePath, '/sample/');
      },
    );

    test('the repository links derive from `repoUrl`', () {
      final config = _config('https://sample.leancode.co');
      expect(
        config.changelogUrl,
        'https://github.com/leancodepl/sample/blob/main/CHANGELOG.md',
      );
      expect(config.issuesUrl, 'https://github.com/leancodepl/sample/issues');
    });

    test('the leancode.co links carry UTM parameters named after the site', () {
      final config = _config('https://sample.leancode.co');
      expect(
        config.leancodeUrl,
        'https://leancode.co/?utm_source=sample-website&utm_medium=referral&utm_campaign=sample',
      );
      expect(
        config.patrolUrl,
        startsWith('https://patrol.leancode.co/?utm_source=sample-website'),
      );
    });

    test('`title` joins the name and the tagline', () {
      expect(
        _config('https://sample.leancode.co').title,
        'sample — A sample package',
      );
    });
  });
}
