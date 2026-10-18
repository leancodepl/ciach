import 'dart:async';

import 'package:ciach_website/components/icons.dart';
import 'package:ciach_website/styles.dart';
import 'package:jaspr/dom.dart';
import 'package:jaspr/jaspr.dart';
import 'package:jaspr_class_scope/jaspr_class_scope.dart';
import 'package:universal_web/js_interop.dart';
import 'package:universal_web/web.dart' as web;

part 'copy_button.scopes.dart';

/// Copies [text] to the clipboard.
///
/// The only interactive island on the page: it is pre-rendered on the server
/// as a plain button and hydrated on the client, so the page stays useful with
/// JavaScript disabled and the shipped script stays tiny.
@client
@scopedCss
class const CopyButton({
  required final String text,

  /// Visible label. Omit for an icon-only button.
  final String? label,

  /// What the button copies, for the tooltip and screen readers.
  final String title = 'Copy to clipboard',

  /// The name of the [Icon] to show. A client component's parameters have to
  /// be serializable, so the icon is named rather than passed.
  final String icon = 'copy',
  super.key,
}) extends StatefulComponent {
  static const _class = _$CopyButtonScope;

  static final _root = _class.root;
  static final _iconOnly = _class('icon-only');
  static final _icon = _class('icon');
  static final _idle = _class('idle');
  static final _done = _class('done');
  static final _isCopied = _class('is-copied');
  static final _label = _class('label');

  @css
  static List<StyleRule> get styles => [
    css(_root.selector, [
      css('&').styles(
        display: .inlineFlex,
        padding: .symmetric(vertical: 0.4.rem, horizontal: 0.7.rem),
        border: hairline(border2Color),
        radius: .circular(8.px),
        cursor: .pointer,
        transition: .combine([
          .new('color', duration: 150.ms, curve: .ease),
          .new('border-color', duration: 150.ms, curve: .ease),
          .new('background-color', duration: 150.ms, curve: .ease),
        ]),
        alignItems: .center,
        gap: .all(0.4.rem),
        color: text2Color,
        fontFamily: fontSans,
        fontSize: 0.78.rem,
        fontWeight: .w600,
        lineHeight: const .expression('1'),
        backgroundColor: surfaceColor,
      ),
      css('&:hover').styles(border: hairline(accentColor), color: textColor),
    ]),
    css(_iconOnly.selector).styles(padding: .all(0.4.rem)),
    css(_icon.selector).styles(display: .inlineFlex),
    css(_done.selector).styles(display: .none, color: okColor),
    css(_isCopied.selector, [
      css('&').styles(border: hairline(okColor), color: okColor),
      css('& ${_idle.selector}').styles(display: .none),
      css('& ${_done.selector}').styles(display: .inlineFlex),
    ]),
  ];

  @override
  State<CopyButton> createState() => _CopyButtonState();
}

class _CopyButtonState() extends State<CopyButton> {
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
      // Best effort: the browser may deny clipboard access, and then the
      // button stays as it was.
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = .new(const .new(seconds: 2), () {
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
        CopyButton._root.name,
        if (label == null) CopyButton._iconOnly.name,
        if (_copied) CopyButton._isCopied.name,
      ].join(' '),
      attributes: {
        'type': 'button',
        'aria-label': component.title,
        'aria-live': 'polite',
        'title': component.title,
      },
      onClick: _copy,
      [
        span(classes: (CopyButton._icon + CopyButton._idle).name, [
          Icon.values.byName(component.icon).build(size: 16),
        ]),
        span(classes: (CopyButton._icon + CopyButton._done).name, [
          Icon.check.build(size: 16),
        ]),
        if (label != null)
          span(classes: CopyButton._label.name, [
            .text(_copied ? 'Copied!' : label),
          ]),
      ],
    );
  }
}
