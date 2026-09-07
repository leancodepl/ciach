import 'dart:async';

import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

/// Copies [text] to the clipboard.
///
/// The only interactive island on the page: it is pre-rendered on the server
/// as a plain button and hydrated on the client, so the page stays useful with
/// JavaScript disabled and the shipped script stays tiny.
@client
class CopyButton extends StatefulComponent {
  const CopyButton({required this.text, this.label, super.key});

  final String text;

  /// Visible label. Omit for an icon-only button.
  final String? label;

  @css
  static List<StyleRule> get styles => [
    css('.copy-button').styles(
      display: .inlineFlex,
      padding: .symmetric(vertical: 0.4.rem, horizontal: 0.7.rem),
      border: hairline(border2Color),
      radius: .circular(8.px),
      cursor: .pointer,
      transition: .combine([
        Transition('color', duration: 150.ms, curve: .ease),
        Transition('border-color', duration: 150.ms, curve: .ease),
        Transition('background-color', duration: 150.ms, curve: .ease),
      ]),
      alignItems: .center,
      gap: .all(0.4.rem),
      color: text2Color,
      backgroundColor: surfaceColor,
      raw: {'font': '600 0.78rem/1 var(--font-sans)'},
    ),
    css('.copy-button:hover')
        .styles(color: textColor, raw: {'border-color': 'var(--accent)'}),
    css('.copy-button-icon').styles(padding: .all(0.4.rem)),
    css('.copy-icon').styles(display: .inlineFlex),
    css('.copy-icon-done').styles(display: .none, color: okColor),
    css('.is-copied')
        .styles(color: okColor, raw: {'border-color': 'var(--ok)'}),
    css('.is-copied .copy-icon-idle').styles(display: .none),
    css('.is-copied .copy-icon-done').styles(display: .inlineFlex),
  ];

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState extends State<CopyButton> {
  bool _copied = false;
  Timer? _resetTimer;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  Future<void> _copy() async {
    if (!kIsWeb) {
      return;
    }
    try {
      await web.window.navigator.clipboard.writeText(component.text).toDart;
    } on Object {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() => _copied = false);
      }
    });
  }

  @override
  Component build(BuildContext context) {
    final label = component.label;
    return button(
      classes: [
        'copy-button',
        if (label == null) 'copy-button-icon',
        if (_copied) 'is-copied',
      ].join(' '),
      attributes: const {
        'type': 'button',
        'aria-label': 'Copy to clipboard',
        'aria-live': 'polite',
        'title': 'Copy to clipboard',
      },
      onClick: _copy,
      [
        span(classes: 'copy-icon copy-icon-idle', [Icon.copy.build(size: 16)]),
        span(classes: 'copy-icon copy-icon-done', [Icon.check.build(size: 16)]),
        if (label != null)
          span(classes: 'copy-label', [.text(_copied ? 'Copied!' : label)]),
      ],
    );
  }
}
