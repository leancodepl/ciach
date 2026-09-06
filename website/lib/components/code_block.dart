import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/highlight.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A highlighted, copyable code sample in a window-like frame.
class const CodeBlock({
  required final String source,
  required final Language language,

  /// Shown in the frame's title bar, e.g. a file name.
  final String? title,

  /// What the copy button copies. Defaults to [source]; pass `''` to hide the
  /// button.
  final String? copyText,

  /// 1-based lines to render struck through as dead code.
  final Set<int> deadLines = const {},
  final bool lineNumbers = false,
  final String? classes,
  super.key,
}) extends StatelessComponent {
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
class const Terminal({
  required final String transcript,
  final String title = 'zsh',

  /// Reveal lines sequentially with a CSS animation (respects
  /// `prefers-reduced-motion`).
  final bool animated = false,
  final String copyText = '',
  super.key,
}) extends StatelessComponent {
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
