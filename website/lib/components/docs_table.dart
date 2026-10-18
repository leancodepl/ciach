/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';

part 'docs_table.scopes.dart';

/// Classes for the tables of the docs page.
@scopedCss
abstract final class DocsTable() {
  static const _class = _$DocsTableScope;

  /// The frame around a table, which scrolls sideways when the table is wider.
  static final wrap = _class('wrap');
  static final table = _class('table');

  /// The comparison table: a mark per tool in each row.
  static final compare = _class('compare');

  /// The chip of a flag that opts back into a skipped category.
  static final flag = _class('flag');

  /// A mark in the comparison table, [yes] or [no].
  static final mark = _class('mark');
  static final yes = _class('yes');
  static final no = _class('no');

  @css
  static List<StyleRule> get styles => [
    css(wrap.selector).styles(
      border: hairline(borderColor),
      radius: const .circular(radius),
      overflow: const .only(x: .auto),
      backgroundColor: surfaceColor,
    ),
    css(table.selector, [
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
            .styles(border: const .only(bottom: .none())),
        css('& th', [
          css('&').styles(fontWeight: .w500),
          css('& code').styles(whiteSpace: .noWrap),
        ]),
      ]),
      css('& td').styles(color: text2Color),
      css('& code${flag.selector}').styles(
        border: hairline(accentAlpha(0.3)),
        color: accentColor,
        whiteSpace: .noWrap,
      ),
      // Tables stack: one card per row, column names as small labels.
      css.media(_stacked, [
        css('& thead').styles(display: .none),
        css('& tbody, & tr, & th, & td').styles(display: .block),
        css('& tr').styles(
          padding: .symmetric(vertical: 0.9.rem, horizontal: 1.1.rem),
          border: .only(bottom: hairlineSide(borderColor)),
        ),
        css('& tbody tr:last-child')
            .styles(border: const .only(bottom: .none())),
        css('& th, & td').styles(padding: .zero, border: .none),
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
    css(compare.selector, [
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
    css(mark.selector).styles(fontWeight: .w700),
    css(yes.selector).styles(color: okColor),
    css(no.selector).styles(color: mutedColor),
  ];

  /// Where tables stack into one card per row.
  static final _stacked = MediaQuery.all(maxWidth: 640.px);
}

/// A table whose first column names each row. [columns] holds the header
/// cells and each row of [rows] one cell per column. On a narrow screen the
/// rows stack, and each cell is labeled with its column.
Component docsTable({
  required List<String> columns,
  required List<List<Component>> rows,
}) => div(classes: DocsTable.wrap.name, [
  table(classes: DocsTable.table.name, [
    thead([
      tr([
        for (final column in columns) th(scope: 'col', [.text(column)]),
      ]),
    ]),
    tbody([
      for (final row in rows)
        tr([
          th(scope: 'row', [row.first]),
          for (final (i, cell) in row.skip(1).indexed)
            td(attributes: {'data-label': columns[i + 1]}, [cell]),
        ]),
    ]),
  ]),
]);
