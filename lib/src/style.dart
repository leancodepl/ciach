import 'dart:io';

import 'package:ciach/src/log.dart' show Level;

/// ANSI styling for one stream; a no-op when not [enabled]. Styles nest.
final class Style {
  const Style({required this.enabled});

  /// The style for [stream].
  factory Style.of(Stdout stream, {bool? color}) => .new(
    enabled: shouldStyle(
      color: color,
      supportsAnsiEscapes: stream.supportsAnsiEscapes,
      environment: Platform.environment,
    ),
  );

  /// [color] if given, else [supportsAnsiEscapes] unless `NO_COLOR` is set.
  static bool shouldStyle({
    required bool? color,
    required bool supportsAnsiEscapes,
    required Map<String, String> environment,
  }) =>
      color ?? (supportsAnsiEscapes && (environment['NO_COLOR'] ?? '').isEmpty);

  /// No styling.
  static const plain = Style(enabled: false);

  final bool enabled;

  // The palette. Roles below pick from it.
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

  /// A `line:column`.
  String position(String text) => _dim(text);

  /// A declaration's kind.
  String kind(String text) => _cyan(text);

  /// Secondary text.
  String note(String text) => _dim(text);

  /// Something to double-check.
  String caution(String text) => _yellow(text);

  /// An error message.
  String failure(String text) => _red(text);

  /// A title or prompt.
  String heading(String text) => _bold(text);

  /// A good outcome.
  String success(String text) => _green(text);

  /// The findings count.
  String attention(String text) => _bold(_yellow(text));

  // The log.

  /// The `error:` label.
  String errorLabel(String text) => _bold(_red(text));

  /// The `warning:` label.
  String warningLabel(String text) => _bold(_yellow(text));

  /// A [Level.CONFIG] record.
  String configuration(String text) => _magenta(text);

  /// Fine records, timestamps, the progress line.
  String detail(String text) => _dim(text);

  String _wrap(String text, int on, int off) =>
      enabled && text.isNotEmpty ? '\x1b[${on}m$text\x1b[${off}m' : text;
}
