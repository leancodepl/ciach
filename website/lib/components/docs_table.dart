import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'docs_table.scopes.dart';

/// A docs table in a scrolling card: the header row's cells and the body
/// rows. On a narrow screen the rows stack into one card each, every cell
/// labeled by its `data-label`. A [compare] table centers its yes/no columns.
@scopedCss
class DocsTable extends StatelessComponent {
  const DocsTable({
    required this.head,
    required this.rows,
    this.compare = false,
    super.key,
  });

  /// The `th`s of the header row.
  final List<Component> head;

  /// The body's `tr`s.
  final List<Component> rows;

  final bool compare;

  static const _class = _$DocsTableScope;

  static final _wrap = _class.root;
  static final _table = _class('table');
  static final _compare = _class('compare');
  static final _mark = _class('mark');
  static final _yes = _class('yes');
  static final _no = _class('no');

  /// A `code` chip naming a flag, in the accent color.
  static final flag = _class('flag');

  /// Where tables stack into one card per row.
  static final _stacked = MediaQuery.all(maxWidth: 640.px);

  /// A yes or no mark for a [compare] cell.
  static Component mark(bool yes) => yes
      ? span(
          classes: (_mark + _yes).name,
          attributes: const {'aria-label': 'yes'},
          const [.text('✓')],
        )
      : span(
          classes: (_mark + _no).name,
          attributes: const {'aria-label': 'no'},
          const [.text('—')],
        );

  @css
  static List<StyleRule> get styles => [
    css(_wrap.selector).styles(
      border: hairline(borderColor),
      radius: const .circular(radius),
      overflow: const .only(x: .auto),
      backgroundColor: surfaceColor,
    ),
    css(_table.selector, [
      css('&').styles(
        width: 100.percent,
        fontSize: 0.95.rem,
        raw: {'border-collapse': 'collapse'},
      ),
      css('& th, & td').styles(
        padding: .symmetric(vertical: 0.9.rem, horizontal: 1.1.rem),
        border: .only(bottom: hairlineSide(borderColor)),
        textAlign: .left,
        raw: {'vertical-align': 'top'},
      ),
      css('& thead th').styles(
        color: mutedColor,
        fontFamily: fontMono,
        fontSize: 0.75.rem,
        fontWeight: .w600,
        textTransform: .upperCase,
        letterSpacing: 0.08.em,
        backgroundColor: surface2Color,
      ),
      css('& tbody', [
        css('& tr:last-child th, & tr:last-child td')
            .styles(raw: {'border-bottom': '0'}),
        css('& th', [
          css('&').styles(fontWeight: .w500),
          css('& code').styles(whiteSpace: .noWrap),
        ]),
      ]),
      // Flag and name columns hug their chips so the prose column gets the
      // room.
      css('&:not(${_compare.selector}) tbody th').styles(width: 1.percent),
      css('& td').styles(color: text2Color),
      css('& code${flag.selector}').styles(
        color: accentColor,
        whiteSpace: .noWrap,
        raw: {'border-color': accentAlpha(0.3).value},
      ),
      // Tables stack: one card per row, column names as small labels.
      css.media(_stacked, [
        css('& thead').styles(display: .none),
        css('& tbody, & tr, & th, & td').styles(display: .block),
        css('& tr').styles(
          padding: .symmetric(vertical: 0.9.rem, horizontal: 1.1.rem),
          border: .only(bottom: hairlineSide(borderColor)),
        ),
        css('& tbody tr:last-child').styles(raw: {'border-bottom': '0'}),
        css('& th, & td').styles(padding: .zero, raw: {'border': '0'}),
        css('& tbody th').styles(
          margin: .only(bottom: 0.5.rem),
          whiteSpace: .normal,
        ),
        css('& td + td').styles(margin: .only(top: 0.5.rem)),
        css('& td[data-label]::before').styles(
          color: mutedColor,
          fontFamily: fontMono,
          fontSize: 0.7.rem,
          fontWeight: .w600,
          textTransform: .upperCase,
          letterSpacing: 0.08.em,
          raw: {'content': "attr(data-label) ': '"},
        ),
      ]),
    ]),
    css(_compare.selector, [
      css("& th[scope='row']").styles(color: text2Color, whiteSpace: .normal),
      css('& thead', [
        css('& th', [
          css('&').styles(textAlign: .center, whiteSpace: .noWrap),
          css('&:first-child').styles(textAlign: .left),
        ]),
        css('& code').styles(textTransform: .none, letterSpacing: .zero),
      ]),
      css('& td', [
        css('&').styles(width: 8.rem, textAlign: .center),
        css.media(_stacked, [css('&').styles(width: .auto, textAlign: .left)]),
      ]),
    ]),
    css(_mark.selector).styles(fontWeight: .w700),
    css(_yes.selector).styles(color: okColor),
    css(_no.selector).styles(color: mutedColor),
  ];

  @override
  Component build(BuildContext context) => div(classes: _wrap.name, [
    table(classes: (_table + (compare ? _compare : null)).name, [
      thead([tr(head)]),
      tbody(rows),
    ]),
  ]);
}
