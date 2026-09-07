import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/highlight.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A highlighted, copyable code sample in a window-like frame.
class CodeBlock extends StatelessComponent {
  const CodeBlock({
    required this.source,
    required this.language,
    this.title,
    this.copyText,
    this.deadLines = const {},
    this.lineNumbers = false,
    this.classes,
    super.key,
  });

  final String source;
  final Language language;

  /// Shown in the frame's title bar, e.g. a file name.
  final String? title;

  /// What the copy button copies. Defaults to [source]; pass `''` to hide the
  /// button.
  final String? copyText;

  /// 1-based lines to render struck through as dead code.
  final Set<int> deadLines;
  final bool lineNumbers;
  final String? classes;

  @css
  static List<StyleRule> get styles => [
    css('.code-block').styles(
      minWidth: .zero,
      margin: .zero,
      border: hairline(borderColor),
      radius: const .circular(radius),
      overflow: .hidden,
      backgroundColor: surfaceColor,
      raw: {'box-shadow': shadow},
    ),
    css('.code-bar').styles(
      display: .flex,
      minHeight: 2.6.rem,
      padding: .only(
        top: 0.4.rem,
        right: 0.6.rem,
        bottom: 0.4.rem,
        left: 0.9.rem,
      ),
      border: .only(bottom: hairlineSide(borderColor)),
      alignItems: .center,
      gap: .all(0.75.rem),
      backgroundColor: surface2Color,
    ),
    css('.code-dots').styles(display: .inlineFlex, gap: .all(0.4.rem)),
    css('.code-dots span').styles(
      width: 10.px,
      height: 10.px,
      radius: .circular(50.percent),
      backgroundColor: const Color('#3a3a45'),
    ),
    css('.code-dots span:first-child').styles(backgroundColor: accentColor),
    css('.code-title').styles(
      minWidth: .zero,
      overflow: .hidden,
      color: mutedColor,
      textAlign: .center,
      fontFamily: fontMono,
      fontSize: 0.75.rem,
      textOverflow: .ellipsis,
      whiteSpace: .noWrap,
      raw: {'flex': '1'},
    ),
    css('.code-block pre').styles(
      padding: .only(
        top: 1.rem,
        right: 1.1.rem,
        bottom: 1.1.rem,
        left: 1.1.rem,
      ),
      margin: .zero,
      overflow: .auto,
      fontSize: 0.8125.rem,
      lineHeight: const .expression('1.65'),
      raw: {
        'tab-size': '2',
        'scrollbar-width': 'thin',
        'scrollbar-color': 'var(--border-2) transparent',
      },
    ),
    css('.code-block code').styles(display: .block, minWidth: .maxContent),
    css('.line').styles(display: .inlineBlock, minWidth: 100.percent),
    // Token colors, shared by the TextMate scopes and ciach's own output.
    css('.tk-keyword').styles(color: const .variable('--tk-keyword')),
    css('.tk-type').styles(color: const .variable('--tk-type')),
    css('.tk-string').styles(color: const .variable('--tk-string')),
    css('.tk-number').styles(color: const .variable('--tk-number')),
    css('.tk-comment').styles(color: const .variable('--tk-comment')),
    css('.tk-annotation').styles(color: const .variable('--tk-annotation')),
    css('.tk-function').styles(color: const .variable('--tk-function')),
    css('.tk-key').styles(color: const .variable('--tk-type')),
    css('.tk-kind').styles(color: const .variable('--tk-keyword')),
    css('.tk-vis').styles(color: const .variable('--tk-comment')),
    css('.tk-hint').styles(color: const .variable('--tk-number')),
    css('.tk-ask').styles(color: const .variable('--tk-annotation')),
    css('.tk-doc')
        .styles(color: const .variable('--tk-comment'), fontStyle: .italic),
    css('.tk-flag').styles(color: accentColor),
    css('.tk-prompt')
        .styles(userSelect: .none, color: accentColor, fontWeight: .w600),
    css('.tk-command').styles(color: textColor, fontWeight: .w600),
    css('.tk-path')
        .styles(color: const .variable('--tk-annotation'), fontWeight: .w600),
    css('.tk-name').styles(color: textColor),
    css('.tk-summary').styles(color: okColor, fontWeight: .w600),
    css('.tk-punct, .tk-operator')
        .styles(color: const .variable('--tk-function')),
    // Transcripts wrap like a real terminal; code blocks keep scrolling because
    // indentation there carries meaning.
    css('.terminal pre').styles(
      color: text2Color,
      whiteSpace: .preWrap,
      raw: {'overflow-wrap': 'anywhere'},
    ),
    css('.terminal code').styles(minWidth: .zero),
    // Wrapped continuations hang under the line's first character.
    css('.terminal .line').styles(
      display: .inlineBlock,
      width: 100.percent,
      minWidth: .zero,
      padding: const .only(left: .expression('2.5ch')),
      textIndent: const .expression('-2.5ch'),
    ),
    // Sequential reveal for animated terminals.
    css('.terminal.animated .line').styles(
      opacity: 0,
      animation: Animation(
        name: 'reveal',
        duration: 350.ms,
        curve: .easeOut,
        fillMode: .forwards,
      ),
      raw: {'animation-delay': 'calc(var(--i, 0) * 110ms + 250ms)'},
    ),
    css.keyframes('reveal', {
      'from': Styles(opacity: 0, transform: .translate(x: (-4).px)),
      'to': const Styles(opacity: 1, transform: .none),
    }),
    css.media(const MediaQuery.raw('(prefers-reduced-motion: reduce)'), [
      css('.terminal.animated .line').styles(opacity: 1),
    ]),
  ];

  @override
  Component build(BuildContext context) {
    final copy = copyText ?? source;
    return figure(
      classes: [
        'code-block',
        // Console output wraps like a terminal; real code scrolls.
        if (language == .console) 'terminal',
        if (lineNumbers) 'numbered',
        ?classes,
      ].join(' '),
      [
        div(classes: 'code-bar', [
          const span(
            classes: 'code-dots',
            attributes: {'aria-hidden': 'true'},
            [span([]), span([]), span([])],
          ),
          if (title case final title?)
            figcaption(classes: 'code-title', [.text(title)])
          else
            const span(classes: 'code-title', []),
          if (copy.isNotEmpty) CopyButton(text: copy),
        ]),
        pre(
          attributes: const {'tabindex': '0'},
          [
            code(
              classes: 'language-${language.name}',
              highlight(source, language, deadLines: deadLines),
            ),
          ],
        ),
      ],
    );
  }
}

/// A terminal transcript whose lines appear one after another.
class Terminal extends StatelessComponent {
  const Terminal({
    required this.transcript,
    this.title = 'zsh',
    this.animated = false,
    this.copyText = '',
    super.key,
  });

  final String transcript;
  final String title;

  /// Reveal lines sequentially with a CSS animation (respects
  /// `prefers-reduced-motion`).
  final bool animated;
  final String copyText;

  @override
  Component build(BuildContext context) {
    return figure(
      classes: animated
          ? 'code-block terminal animated'
          : 'code-block terminal',
      [
        div(classes: 'code-bar', [
          const span(
            classes: 'code-dots',
            attributes: {'aria-hidden': 'true'},
            [span([]), span([]), span([])],
          ),
          figcaption(classes: 'code-title', [.text(title)]),
          if (copyText.isNotEmpty) CopyButton(text: copyText),
        ]),
        pre(
          attributes: const {'tabindex': '0'},
          [
            code([
              for (final (index, line) in highlightLines(
                transcript,
                .console,
              ).indexed) ...[
                if (index > 0) const .text('\n'),
                span(
                  classes: 'line',
                  styles: animated ? Styles(raw: {'--i': '$index'}) : null,
                  line,
                ),
              ],
            ]),
          ],
        ),
      ],
    );
  }
}
