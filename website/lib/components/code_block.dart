import 'package:ciach_website/components/copy_button.dart';
import 'package:ciach_website/highlight.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';

/// A highlighted, copyable code sample in a window-like frame.
class CodeBlock extends StatelessComponent {
  const CodeBlock({
    required this.code,
    required this.language,
    this.title,
    this.copyText,
    this.deadLines = const {},
    this.lineNumbers = false,
    this.classes,
    super.key,
  });

  final String code;
  final Language language;

  /// Shown in the frame's title bar, e.g. a file name.
  final String? title;

  /// What the copy button copies. Defaults to [code]; pass `''` to hide the
  /// button.
  final String? copyText;

  /// 1-based lines to render struck through as dead code.
  final Set<int> deadLines;
  final bool lineNumbers;
  final String? classes;

  @override
  Component build(BuildContext context) {
    final copy = copyText ?? code;
    return figure(
      classes: ['code-block', if (lineNumbers) 'numbered', ?classes].join(' '),
      [
        div(classes: 'code-bar', [
          const span(
            classes: 'code-dots',
            attributes: {'aria-hidden': 'true'},
            [span([]), span([]), span([])],
          ),
          if (title case final title?)
            figcaption(classes: 'code-title', [Component.text(title)])
          else
            const span(classes: 'code-title', []),
          if (copy.isNotEmpty) CopyButton(text: copy),
        ]),
        pre(
          attributes: const {'tabindex': '0'},
          [
            Component.element(
              tag: 'code',
              classes: 'language-${language.name}',
              children: highlight(code, language, deadLines: deadLines),
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
    final lines = transcript.split('\n');
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
          figcaption(classes: 'code-title', [Component.text(title)]),
          if (copyText.isNotEmpty) CopyButton(text: copyText),
        ]),
        pre(
          attributes: const {'tabindex': '0'},
          [
            code([
              for (final (index, line) in lines.indexed) ...[
                if (index > 0) const Component.text('\n'),
                span(
                  classes: 'line',
                  styles: animated ? Styles(raw: {'--i': '$index'}) : null,
                  highlight(line, Language.console),
                ),
              ],
            ]),
          ],
        ),
      ],
    );
  }
}
