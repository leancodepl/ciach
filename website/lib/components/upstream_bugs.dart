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
    required this.commit,
    this.fixedByUs = false,
  });

  /// The issue number in dart-lang/sdk.
  final int issue;
  final String title;

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
    title: 'Missed references from object patterns in other files',
    commit: 'e837b597586e81afc9a4094f2148fe39e9aa806f',
    fixedByUs: true,
  ),
  _Bug(
    issue: 63944,
    title: 'Dot shorthands hidden by a local of the same name',
    commit: '1cc49b4eeca5c593f970b74bbc1606c318fcaf40',
    fixedByUs: true,
  ),
  _Bug(
    issue: 64422,
    title: 'References to an `Object` member override threw',
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

  static final _list = _class('list');
  static final _bug = _class('bug');
  static final _issue = _class('issue');
  static final _title = _class('title');

  @css
  static List<StyleRule> get styles => [
    css(_list.selector).styles(
      border: hairline(borderColor),
      radius: const .circular(radius),
      overflow: .hidden,
      backgroundColor: surfaceColor,
    ),
    css(_bug.selector, [
      css('&').styles(
        display: .flex,
        padding: .symmetric(vertical: 0.9.rem, horizontal: 1.25.rem),
        flexWrap: .wrap,
        alignItems: .center,
        gap: .new(row: 0.4.rem, column: 1.rem),
      ),
      css('& + &').styles(border: .only(top: hairlineSide(borderColor))),
    ]),
    css(_issue.selector, [
      css('&')
          .styles(color: mutedColor, fontFamily: fontMono, fontSize: 0.85.rem),
      css('&:hover').styles(color: accentColor),
    ]),
    css(_title.selector)
        .styles(minWidth: .zero, color: textColor, raw: {'flex': '1 1 16rem'}),
  ];

  @override
  Component build(BuildContext context) {
    return Section(
      id: 'upstream',
      eyebrow: 'Upstream',
      heading: 'It finds bugs in the analyzer, too.',
      lead:
          'Asking for the references of every declaration turns up what an '
          'editor rarely hits. We reported these to the Dart SDK, and fixed '
          'some ourselves.',
      children: [
        ul(classes: _list.name, [
          for (final bug in _bugs)
            li(classes: _bug.name, [
              externalLink(
                bug.issueUrl,
                classes: _issue.name,
                label: 'dart-lang/sdk issue ${bug.issue}',
                [.text('#${bug.issue}')],
              ),
              span(classes: _title.name, rich(bug.title)),
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
      ],
    );
  }
}
