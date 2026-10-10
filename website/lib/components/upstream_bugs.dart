import 'package:ciach_website/components/card.dart';
import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/components/pill.dart';
import 'package:ciach_website/components/section.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'upstream_bugs.scopes.dart';

class _Bug {
  const _Bug({
    required this.issue,
    required this.title,
    required this.body,
    required this.commit,
    this.fixedByUs = false,
  });

  /// The issue number in dart-lang/sdk.
  final int issue;
  final String title;
  final String body;

  /// The dart-lang/sdk commit that fixed it.
  final String commit;

  /// Whether one of ciach's maintainers wrote the fix.
  final bool fixedByUs;

  String get issueUrl => 'https://github.com/dart-lang/sdk/issues/$issue';
  String get commitUrl => 'https://github.com/dart-lang/sdk/commit/$commit';
}

const _bugs = [
  _Bug(
    issue: 63903,
    title: 'References from an object pattern in another file went missing',
    body:
        'A getter used only as `A(foo: _)` in a different library had no '
        'references at all, so it looked unused.',
    commit: 'e837b597586e81afc9a4094f2148fe39e9aa806f',
    fixedByUs: true,
  ),
  _Bug(
    issue: 63944,
    title: 'Dot shorthands lost to a local variable of the same name',
    body:
        'With a local `foo` in scope, `.foo` disappeared from Find References, '
        'rename and Extract Method.',
    commit: '1cc49b4eeca5c593f970b74bbc1606c318fcaf40',
    fixedByUs: true,
  ),
  _Bug(
    issue: 64422,
    title: 'References to an `Object` member override threw',
    body:
        'Asking for the references of a `toString()` override failed with a '
        'type error once the library had a primary constructor.',
    commit: '767a1e28c4c15f2dfe860e1e63493e82b0b80dfe',
  ),
];

/// The analysis server bugs ciach turned up, linked to their dart-lang/sdk
/// issues, with the ones we fixed ourselves marked as such.
/// `doc/upstream_bugs.md` at the repository root keeps the same list.
@scopedCss
class UpstreamBugs extends StatelessComponent {
  const UpstreamBugs({super.key});

  static const _class = _$UpstreamBugsScope;

  static final _grid = _class('grid');
  static final _bug = _class('bug');
  static final _issue = _class('issue');
  static final _badges = _class('badges');

  @css
  static List<StyleRule> get styles => [
    css(_grid.selector, [
      css('&').styles(
        display: .grid,
        gap: .all(1.rem),
        raw: {
          'grid-template-columns':
              'repeat(auto-fit, minmax(min(100%, 300px), 1fr))',
        },
      ),
      shrinkableChildren(),
    ]),
    css(_bug.selector, [
      css('&')
          .styles(display: .flex, flexDirection: .column, gap: .all(0.6.rem)),
      css('&:hover').styles(
        transform: .translate(y: (-2).px),
        raw: {'border-color': 'var(--border-2)'},
      ),
      css('& h3').styles(margin: .zero),
      css('& p').styles(raw: {'flex': '1'}),
    ]),
    css(_issue.selector, [
      css('&').styles(
        display: .inlineFlex,
        alignItems: .center,
        gap: .all(0.35.rem),
        color: mutedColor,
        fontFamily: fontMono,
        fontSize: 0.85.rem,
      ),
      css('&:hover').styles(color: accentColor),
    ]),
    css(_badges.selector).styles(
      display: .flex,
      margin: .only(top: 0.4.rem),
      flexWrap: .wrap,
      gap: .all(0.5.rem),
    ),
  ];

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'upstream',
      eyebrow: 'Upstream',
      heading: 'It finds bugs in the analyzer, too.',
      lead:
          'ciach asks the analysis server for the references of every '
          'declaration in a project, which is more than most editors ever do. '
          'Where an answer came back wrong, we reported it to the Dart SDK, '
          'and fixed some of them ourselves.',
      children: [
        ul(classes: _grid.name, [
          for (final bug in _bugs)
            Card(classes: _bug, listItem: true, [
              externalLink(
                bug.issueUrl,
                classes: _issue.name,
                label: 'dart-lang/sdk issue ${bug.issue}',
                [
                  .text('dart-lang/sdk#${bug.issue}'),
                  Icon.external.build(size: 14),
                ],
              ),
              h3(rich(bug.title)),
              p(rich(bug.body)),
              div(classes: _badges.name, [
                if (bug.fixedByUs)
                  Pill(
                    'Fixed by us',
                    href: bug.commitUrl,
                    accent: true,
                    icon: .check,
                  )
                else
                  Pill('Fixed by the Dart team', href: bug.commitUrl),
              ]),
            ]),
        ]),
      ],
    );
  }
}
