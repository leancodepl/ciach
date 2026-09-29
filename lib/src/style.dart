import 'dart:io';

import 'package:ciach/src/log.dart' show Level;

/// ANSI styling for one output stream. Every method returns its text
/// unchanged when [enabled] is `false`, so rendering code styles
/// unconditionally.
///
/// Each style resets only what it set (`22` for bold and dim, `39` for a
/// color), so styles nest: `bold(red('x'))`.
final class Style {
  const Style({required this.enabled});

  /// The style for [stream]; see [shouldStyle].
  factory Style.of(Stdout stream, {bool? color}) => Style(
    enabled: shouldStyle(
      color: color,
      supportsAnsiEscapes: stream.supportsAnsiEscapes,
      environment: Platform.environment,
    ),
  );

  /// [color] when given (`--color`/`--no-color`), else whether the stream
  /// [supportsAnsiEscapes], unless `NO_COLOR` is set in [environment]
  /// (https://no-color.org).
  static bool shouldStyle({
    required bool? color,
    required bool supportsAnsiEscapes,
    required Map<String, String> environment,
  }) =>
      color ?? (supportsAnsiEscapes && (environment['NO_COLOR'] ?? '').isEmpty);

  /// No styling.
  static const plain = Style(enabled: false);

  final bool enabled;

  // The palette: every role below is one of these, so a change of color is
  // a change here.
  String _bold(String text) => _wrap(text, 1, 22);
  String _dim(String text) => _wrap(text, 2, 22);
  String _red(String text) => _wrap(text, 31, 39);
  String _green(String text) => _wrap(text, 32, 39);
  String _yellow(String text) => _wrap(text, 33, 39);
  String _magenta(String text) => _wrap(text, 35, 39);
  String _cyan(String text) => _wrap(text, 36, 39);

  // The report.

  /// A file header.
  String path(String text) => _bold(text);

  /// A `line:column`, or a `used at …` location.
  String position(String text) => _dim(text);

  /// A declaration's kind.
  String kind(String text) => _cyan(text);

  /// Secondary text: visibility, hints, what a section means, timings.
  String note(String text) => _dim(text);

  /// Something to look at before trusting or acting on the result.
  String caution(String text) => _yellow(text);

  /// Why something failed: an exception's message.
  String failure(String text) => _red(text);

  /// A section's title, or a question put to the user.
  String heading(String text) => _bold(text);

  /// Something that went as hoped.
  String success(String text) => _green(text);

  /// Findings the user asked to hear about.
  String attention(String text) => _bold(_yellow(text));

  // The log.

  /// The `error:` label.
  String errorLabel(String text) => _bold(_red(text));

  /// The `warning:` label.
  String warningLabel(String text) => _bold(_yellow(text));

  /// A [Level.CONFIG] record: how the run is set up.
  String configuration(String text) => _magenta(text);

  /// A record finer than [Level.CONFIG], a timestamp, a logger's name, or
  /// the progress line.
  String detail(String text) => _dim(text);

  String _wrap(String text, int on, int off) =>
      enabled && text.isNotEmpty ? '\x1b[${on}m$text\x1b[${off}m' : text;
}
