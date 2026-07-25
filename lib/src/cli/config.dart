import 'dart:io';

import 'package:ciach/src/cli/args.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// The file name looked for when discovering a config in the project
/// directory.
const configFileName = 'ciach.yaml';

/// Every key a config file may contain. Each one mirrors the command-line
/// flag of the same name (`path` mirrors the positional path argument), so
/// there is exactly one name to learn per setting.
const configKeys = <String>{
  'path',
  'public',
  'generated',
  'overrides',
  'operators',
  'unused-union-members',
  'report-tojson',
  'set-exit-if-changed',
  'remove',
  'force',
  'exclude',
  'include',
  'generated-suffix',
  'kinds',
  'format',
  'color',
  'progress',
  'verbose',
  'concurrency',
  'dart',
};

/// A config file: the settings it holds, where it came from, and typed readers
/// for pulling values out of it.
///
/// Deliberately *not* a field per option. The options are already declared once
/// in `buildParser`, and `resolveOptions` is the one place that reads them all;
/// a second hand-written list of the same twenty names would only be something
/// to forget to update. What the file sets lives in [settings] — validated on
/// the way in for shape and unknown keys, and on the way out for type — while
/// `ResolvedOptions` is where a run's settings become properly typed and
/// non-nullable.
class ConfigFile {
  const ConfigFile._({
    required this.settings,
    required this.path,
    required this.ignored,
  });

  /// A config that sets nothing, from nowhere.
  const ConfigFile.empty() : settings = const {}, path = null, ignored = false;

  /// Parses [source] as a config file whose settings came from [origin]
  /// (a file path, which becomes [path] and names the file in errors).
  ///
  /// Throws a [FormatException] on a document that isn't a map of options, or
  /// one carrying a key that is not in [configKeys]. Individual values are
  /// checked as they are read, by the readers below.
  factory ConfigFile.parse(String source, {required String origin}) {
    final Object? document;
    try {
      document = loadYaml(source, sourceUrl: Uri.file(origin));
    } on YamlException catch (e) {
      throw FormatException('$origin: not valid YAML: ${e.message}');
    }

    // An empty file parses to null; treat it as "no settings", not an error.
    if (document == null) {
      return ConfigFile._(settings: const {}, path: origin, ignored: false);
    }
    if (document is! Map) {
      throw FormatException('$origin: the top level must be a map of options.');
    }

    final unknown = document.keys
        .map((key) => '$key')
        .where((key) => !configKeys.contains(key))
        .toList();
    if (unknown.isNotEmpty) {
      final valid = (configKeys.toList()..sort()).join(', ');
      throw FormatException(
        '$origin: unknown option${unknown.length == 1 ? '' : 's'} ${unknown.map((key) => "'$key'").join(', ')}. Valid options: $valid.',
      );
    }

    return ConfigFile._(
      settings: {
        for (final entry in document.entries)
          // A key with no value (`public:`) counts as unset, so commenting a
          // value out behaves like deleting the line. YAML collections are
          // unwrapped so settings holds plain Dart values.
          if (entry.value case final value?)
            '${entry.key}': value is Iterable ? value.toList() : value,
      },
      path: origin,
      ignored: false,
    );
  }

  /// Finds and reads the config file for a run.
  ///
  /// [explicitPath] — from `--config` — is read as-is; otherwise
  /// [configFileName] is looked for in [projectDir]. With [ignore] set the file
  /// is located (so `--verbose` can name what it skipped) but never read, which
  /// is what makes `--no-config` survive an unparseable config file.
  ///
  /// Throws a [FormatException] when [explicitPath] does not exist, or when the
  /// file cannot be read or parsed.
  static ConfigFile load({
    required String projectDir,
    String? explicitPath,
    bool ignore = false,
  }) {
    final discovered = File(p.join(projectDir, configFileName));
    if (ignore) {
      return ConfigFile._(
        settings: const {},
        path: discovered.existsSync() ? discovered.path : null,
        ignored: true,
      );
    }

    final File file;
    if (explicitPath != null) {
      file = File(explicitPath);
      if (!file.existsSync()) {
        throw FormatException('Config file does not exist: $explicitPath');
      }
    } else {
      if (!discovered.existsSync()) {
        return const ConfigFile.empty();
      }
      file = discovered;
    }

    try {
      return ConfigFile.parse(file.readAsStringSync(), origin: file.path);
    } on FileSystemException catch (e) {
      throw FormatException(
        'Cannot read config file ${file.path}: ${e.message}',
      );
    }
  }

  /// What the file sets, keyed by config key, in the order it set them. Only
  /// keys the file actually carries a value for appear.
  final Map<String, Object?> settings;

  /// The file these settings came from, or — when [ignored] — the file that was
  /// skipped. `null` when there was no config file at all.
  final String? path;

  /// Whether a config file was deliberately skipped (`--no-config`). Nothing
  /// was read or parsed in that case, so even an invalid file is no error.
  final bool ignored;

  /// A boolean setting, or `null` when the file doesn't set it.
  bool? boolean(String key) => switch (settings[key]) {
    null => null,
    final bool value => value,
    final other => _wrong(key, 'true or false', other),
  };

  /// A string setting, or `null` when the file doesn't set it.
  String? string(String key) => switch (settings[key]) {
    null => null,
    final String value => value,
    final other => _wrong(key, 'a string', other),
  };

  /// A string setting restricted to [allowed] values.
  String? oneOf(String key, List<String> allowed) {
    final value = string(key);
    if (value != null && !allowed.contains(value)) {
      throw FormatException(
        "$path: '$key' must be one of ${allowed.join(', ')}, got '$value'.",
      );
    }
    return value;
  }

  /// A list-of-strings setting, also accepting a bare string as a one-element
  /// list (`exclude: test/**`).
  List<String>? strings(String key) => switch (settings[key]) {
    null => null,
    final String value => [value],
    final Iterable<Object?> values => [
      for (final value in values)
        if (value is String) value else _wrong(key, 'a list of strings', value),
    ],
    final other => _wrong(key, 'a list of strings', other),
  };

  /// Declaration kind names, left for `parseKinds` to turn into symbol kinds
  /// but validated here, so an unknown kind names the file it came from.
  List<String>? kinds(String key) {
    final values = strings(key);
    if (values != null) {
      try {
        parseKinds(values);
      } on FormatException catch (e) {
        throw FormatException("$path: '$key': ${e.message}");
      }
    }
    return values;
  }

  /// A positive-integer setting, or `null` when the file doesn't set it.
  int? positiveInt(String key) => switch (settings[key]) {
    null => null,
    final int value when value > 0 => value,
    final other => _wrong(key, 'a positive integer', other),
  };

  /// Reports a value of the wrong type, naming the file and the key.
  Never _wrong(String key, String expected, Object? value) =>
      throw FormatException(
        "$path: '$key' must be $expected, got ${_describe(value)}.",
      );

  static String _describe(Object? value) => switch (value) {
    null => 'null',
    String() => 'a string',
    bool() => 'a boolean',
    num() => 'a number',
    Iterable() => 'a list',
    Map() => 'a map',
    _ => '$value',
  };
}
