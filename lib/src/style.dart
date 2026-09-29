import 'dart:io';

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

  String bold(String text) => _wrap(text, 1, 22);
  String dim(String text) => _wrap(text, 2, 22);
  String red(String text) => _wrap(text, 31, 39);
  String green(String text) => _wrap(text, 32, 39);
  String yellow(String text) => _wrap(text, 33, 39);
  String cyan(String text) => _wrap(text, 36, 39);

  /// An `error:` label, or anything that stopped the run.
  String error(String text) => bold(red(text));

  /// A `warning:` label, or anything the user should look at.
  String warning(String text) => bold(yellow(text));

  /// Something that went as hoped.
  String success(String text) => green(text);

  /// Secondary text: locations, hints, timings.
  String hint(String text) => dim(text);

  String _wrap(String text, int on, int off) =>
      enabled && text.isNotEmpty ? '\x1b[${on}m$text\x1b[${off}m' : text;
}
