import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:leancode_site/src/components/footer.dart';
import 'package:leancode_site/src/components/nav_bar.dart';
import 'package:leancode_site/src/styles.dart';

part 'shell.scopes.dart';

/// Skip link, header, `<main>` and footer around a page's content.
///
/// [path] is the page's own path, `/` or `/docs/concepts`: the skip link's
/// anchor is relative to it, because a bare `#fragment` would resolve
/// against the document's `<base href>`, and the navigation marks the docs
/// link as current when the path starts with the site's docs path.
@scopedCss
class PageShell extends StatelessComponent {
  const PageShell({
    required this.path,
    required this.footer,
    required this.children,
    super.key,
  });

  final String path;
  final SiteFooter footer;
  final List<Component> children;

  static const _class = _$PageShellScope;

  static final _skipLink = _class('skip-link');

  @css
  static List<StyleRule> get styles => [
    css(_skipLink.selector, [
      css('&').styles(
        position: .fixed(top: 12.px, left: 12.px),
        zIndex: const .new(100),
        padding: .symmetric(vertical: 0.6.rem, horizontal: 1.rem),
        radius: const .circular(radiusSm),
        transition: .new('transform', duration: 200.ms, curve: .ease),
        transform: .translate(y: (-200).percent),
        color: accentInkColor,
        fontWeight: .w600,
        backgroundColor: accentColor,
      ),
      css('&:focus').styles(transform: const .translate(y: .zero)),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    return .fragment([
      a(href: '$path#main', classes: _skipLink.name, const [
        .text('Skip to content'),
      ]),
      NavBar(path: path),
      main_(id: 'main', children),
      footer,
    ]);
  }
}
