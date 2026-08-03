import 'dart:io';

import 'package:ciach/src/cli/args.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Every key a config file may contain, following [CiachOption].
final configKeys = {for (final option in CiachOption.values) ?option.configKey};

/// The config-file layer of option resolution: a [ConfigurationBroker] over the
/// settings of a `ciach.yaml`.
///
/// Where to look for that file, whether to read it at all, and reporting a
/// malformed one against its path stay ciach's own business; the command line
/// beating it, and its defaults, are `package:config`'s.
class ConfigFile implements ConfigurationBroker<CiachOption<dynamic>> {
  const ConfigFile._({
    required this.settings,
    required this.path,
    required this.ignored,
  });

  /// Creates a config that sets nothing, from nowhere.
  const ConfigFile.empty() : settings = const {}, path = null, ignored = false;

  /// Parses [source], read from the file [origin], which names it in errors.
  ///
  /// Throws a [FormatException] on anything but a map of known keys with values
  /// their options accept.
  factory ConfigFile.parse(String source, {required String origin}) {
    final Object? document;
    try {
      document = loadYaml(source, sourceUrl: Uri.file(origin));
    } on YamlException catch (e) {
      throw FormatException('$origin: not valid YAML: ${e.message}');
    }

    // An empty file parses to null; that is no settings, not an error.
    if (document == null) {
      return ._(settings: const {}, path: origin, ignored: false);
    }
    if (document is! Map) {
      throw FormatException('$origin: the top level must be a map of options.');
    }

    final unknown = document.keys
        .map((key) => '$key')
        .whereNot(configKeys.contains)
        .toList();
    if (unknown.isNotEmpty) {
      final valid = (configKeys.toList()..sort()).join(', ');
      throw FormatException(
        '$origin: unknown option${unknown.length == 1 ? '' : 's'} ${unknown.map((key) => "'$key'").join(', ')}. Valid options: $valid.',
      );
    }

    final file = ConfigFile._(
      settings: {
        for (final entry in document.entries)
          // A valueless key (`public:`) counts as unset, and YAML collections
          // are unwrapped to plain Dart ones.
          if (entry.value case final value?)
            '${entry.key}': value is Iterable ? value.toList() : value,
      },
      path: origin,
      ignored: false,
    );

    // Resolution only asks for the keys it needs, so without checking the whole
    // file here, a bad value under an overridden option would go unreported.
    file.settings.keys.forEach(file._typedValue);
    return file;
  }

  /// Finds and reads the config file for a run: [explicitPath] from `--config`
  /// if given, else [configFileName] in [projectDir].
  ///
  /// With [ignore] the file is located but never read, so a caller can still
  /// name what `--no-config` skipped, and an unparseable file is no error.
  ///
  /// Throws a [FormatException] if [explicitPath] is missing or the file cannot
  /// be read or parsed.
  static ConfigFile load({
    required String projectDir,
    String? explicitPath,
    bool ignore = false,
  }) {
    final discovered = File(p.join(projectDir, configFileName));
    if (ignore) {
      return ._(
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
        return const .empty();
      }
      file = discovered;
    }

    try {
      return .parse(file.readAsStringSync(), origin: file.path);
    } on FileSystemException catch (e) {
      throw FormatException(
        'Cannot read config file ${file.path}: ${e.message}',
      );
    }
  }

  /// What the file sets, keyed by config key, in the order it set them.
  final Map<String, Object?> settings;

  /// The file the [settings] came from, or that [ignored] skipped; `null` when
  /// there was no config file at all.
  final String? path;

  /// Whether `--no-config` skipped a file, leaving it unread.
  final bool ignored;

  /// The value for [key], a JSON pointer such as `/public`.
  @override
  Object? valueOrNull(String key, CiachConfiguration cfg) =>
      _typedValue(key.startsWith('/') ? key.substring(1) : key);

  /// The value under [key], as the type its option takes.
  ///
  /// The type comes from the option, not the value, so that `exclude: ['a']`
  /// arrives as the `List<String>` the option needs rather than a
  /// `List<dynamic>`, and a mismatch names the file and the key.
  ///
  /// The first three accept less than their type allows, and `package:config`
  /// keeps its own validators internal, so they reuse what the options declare.
  Object? _typedValue(String key) => switch (_optionFor(key)) {
    .format => _oneOf(key, formatNames),
    .kinds => _kinds(key),
    .concurrency => _positiveInt(key),
    final option => switch (option.option) {
      FlagOption() => _boolean(key),
      IntOption() => _positiveInt(key),
      MultiOption() => _strings(key),
      _ => _string(key),
    },
  };

  CiachOption<dynamic> _optionFor(String key) =>
      .values.firstWhere((option) => option.configKey == key);

  bool? _boolean(String key) => switch (settings[key]) {
    null => null,
    final bool value => value,
    final other => _wrong(key, 'true or false', other),
  };

  String? _string(String key) => switch (settings[key]) {
    null => null,
    final String value => value,
    final other => _wrong(key, 'a string', other),
  };

  /// The strings under [key], accepting a bare string as a one-element list.
  List<String>? _strings(String key) => switch (settings[key]) {
    null => null,
    final String value => [value],
    final Iterable<Object?> values => [
      for (final value in values)
        if (value is String) value else _wrong(key, 'a list of strings', value),
    ],
    final other => _wrong(key, 'a list of strings', other),
  };

  /// The string under [key], which has to be one of [allowed].
  String? _oneOf(String key, List<String> allowed) {
    final value = _string(key);
    if (value != null && !allowed.contains(value)) {
      throw FormatException(
        "$path: '$key' must be one of ${allowed.join(', ')}, got '$value'.",
      );
    }
    return value;
  }

  /// The kind names under [key], validated but not yet converted.
  List<String>? _kinds(String key) {
    final values = _strings(key);
    if (values != null) {
      try {
        parseKinds(values);
      } on FormatException catch (e) {
        throw FormatException("$path: '$key': ${e.message}");
      }
    }
    return values;
  }

  int? _positiveInt(String key) => switch (settings[key]) {
    null => null,
    final int value && > 0 => value,
    final other => _wrong(key, 'a positive integer', other),
  };

  /// Reports the wrong type, naming the file and the key.
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
