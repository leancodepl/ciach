/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 */

import 'package:jaspr/jaspr.dart';

/// What a site says about itself. The shared components read it through
/// [Site.of]: the navigation and footer link to [repoUrl] and [pubUrl], the
/// hero shows [installCommand] and [version], the social card and the
/// structured data describe the package.
class SiteConfig {
  const SiteConfig({
    required this.name,
    required this.tagline,
    required this.description,
    required this.siteUrl,
    required this.version,
    required this.repoUrl,
    required this.pubUrl,
    required this.installCommand,
    required this.logo,
    required this.keywords,
    this.alternateName,
    this.runtimePlatform = 'Dart',
    this.docsPath = '/docs',
    this.licenseName = 'Apache-2.0',
    this.licenseUrl = 'https://www.apache.org/licenses/LICENSE-2.0',
    String? utmSource,
  }) : _utmSource = utmSource;

  /// The package name, also the site's name: `ciach`.
  final String name;

  /// The one-line pitch under the name.
  final String tagline;

  /// What the package does, for crawlers and link unfurlers, under 160
  /// characters.
  final String description;

  /// Public URL of the deployed site, with or without a trailing slash.
  final String siteUrl;

  /// The package version shown across the site.
  final String version;

  final String repoUrl;
  final String pubUrl;

  /// The first command a reader runs: `dart install ciach`.
  final String installCommand;

  /// The word mark, drawn in the navigation, the footer and the social card,
  /// which asks for the large one.
  final Component Function({bool large}) logo;

  /// What the package is about, for the structured data.
  final List<String> keywords;

  /// A longer name for the structured data: `ciach dead code detector`.
  final String? alternateName;

  /// What the package runs on, for the structured data: `Dart SDK 3.10+`.
  final String runtimePlatform;

  /// Where the docs start, relative to the site root.
  final String docsPath;

  /// The license as the footer names it, and the URL the structured data
  /// points at.
  final String licenseName;
  final String licenseUrl;

  final String? _utmSource;

  /// [siteUrl] with a guaranteed trailing slash, for canonical and Open Graph
  /// URLs.
  String get canonicalUrl => siteUrl.endsWith('/') ? siteUrl : '$siteUrl/';

  /// The `<base href>` derived from [siteUrl], so relative asset paths still
  /// resolve if the site is served from a sub-path.
  String get basePath {
    final path = Uri.parse(siteUrl).path;
    if (path.isEmpty || path == '/') {
      return '/';
    }
    return path.endsWith('/') ? path : '$path/';
  }

  /// `name — tagline`, the title of the landing page and the social card.
  String get title => '$name — $tagline';

  String get changelogUrl => '$repoUrl/blob/main/CHANGELOG.md';
  String get issuesUrl => '$repoUrl/issues';

  /// The UTM parameters on links to leancode.co, so that visits from the site
  /// can be told apart.
  String get _utm {
    final source = _utmSource ?? '$name-website';
    return 'utm_source=$source&utm_medium=referral&utm_campaign=$name';
  }

  String get leancodeUrl => 'https://leancode.co/?$_utm';
  String get leancodeEstimateUrl => 'https://leancode.co/get-estimate?$_utm';
  String get patrolUrl => 'https://patrol.leancode.co/?$_utm';
  static const leancodePackagesUrl =
      'https://pub.dev/packages?q=publisher%3Aleancode.co&sort=downloads';
}

/// Makes a [SiteConfig] available to every component below it; a site wraps
/// its `Document` in one.
class Site extends InheritedComponent {
  const Site({required this.config, required super.child, super.key});

  final SiteConfig config;

  /// The site's configuration.
  static SiteConfig of(BuildContext context) =>
      context.dependOnInheritedComponentOfExactType<Site>()?.config ??
      (throw StateError(
        'No Site above this component; wrap the Document in one.',
      ));

  @override
  bool updateShouldNotify(Site oldComponent) => config != oldComponent.config;
}
