import 'package:ciach/src/project_config/project_files.dart';

/// Globs that match the Dart files declared by a builder's `build_extensions`.
/// The expansion mirrors `expectedOutputs` from package:build, up to version
/// 2.3, which allowed `^` without a capture.
Iterable<String> outputGlobs(Map<Object?, Object?> buildExtensions) => [
  for (final MapEntry(key: input, value: outputs) in buildExtensions.entries)
    if (input is String)
      for (final output in _dartOutputs(outputs)) _outputGlob(input, output),
];

Iterable<String> _dartOutputs(Object? outputs) => switch (outputs) {
  final String one => [one],
  final List<Object?> many => many.whereType<String>(),
  _ => const <String>[],
}.where((output) => output.endsWith('.dart') && output != '.dart');

String _outputGlob(String input, String output) => switch (input) {
  _ when _captureGroup.hasMatch(input) => _capturedOutputGlob(input, output),
  r'$package$' => escapeGlob(output),
  _ when input.startsWith('^') => escapeGlob(output),
  r'$lib$' => 'lib/${escapeGlob(output)}',
  _ => '**${escapeGlob(output)}',
};

/// The glob for an output whose input contains a `{{capture}}`. Such an input
/// matches the end of a path, or the whole path when it starts with `^` or
/// with a capture.
String _capturedOutputGlob(String input, String output) {
  final glob = output.splitMapJoin(
    _captureGroup,
    onMatch: (_) => '**',
    onNonMatch: escapeGlob,
  );
  final wholePath = input.startsWith('^') || input.startsWith('{{');
  return wholePath ? glob : '**$glob';
}

final _captureGroup = RegExp(r'\{\{\w*\}\}');
