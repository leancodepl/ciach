import 'dart:io';

import 'package:ciach/src/cli/args.dart';
import 'package:collection/collection.dart';
import 'package:config/config.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// Every key a config file may contain: the config key of each option that
/// declares one, so the accepted set follows [CiachOption] rather than being
/// maintained alongside it.
final configKeys = {for (final option in CiachOption.values) ?option.configKey};

/// A config file: the settings it holds, where it came from, and the typed
/// lookups that hand them to `package:config`.
///
/// As a [ConfigurationBroker] this is the config-file layer of option
/// resolution — the command line still wins, and the option's own default is
/// still the fallback. What stays ciach's own business is everything about the
/// file itself: where to look for it, whether to read it at all, and reporting
/// a malformed one against the path it came from.
class ConfigFile implements ConfigurationBroker<CiachOption<dynamic>> {
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
  /// Throws a [FormatException] on a document that isn't a map of options, one
  /// carrying a key that is not in [configKeys], or a value whose type doesn't
  /// suit its option.
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
          // A key with no value (`public:`) counts as unset, so commenting a
          // value out behaves like deleting the line. YAML collections are
          // unwrapped so settings holds plain Dart values.
          if (entry.value case final value?)
            '${entry.key}': value is Iterable ? value.toList() : value,
      },
      path: origin,
      ignored: false,
    );

    // Type-check the whole file up front. Resolution only asks for the keys it
    // ends up needing, so without this a bad value under an option the command
    // line overrides would sit in the file unreported.
    file.settings.keys.forEach(file._typedValue);
    return file;
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

  /// The config-file value for [key] — a JSON pointer such as `/public` —
  /// typed to suit its option, or `null` when the file doesn't set it.
  @override
  Object? valueOrNull(String key, CiachConfiguration cfg) =>
      _typedValue(key.startsWith('/') ? key.substring(1) : key);

  /// The value under [key], as the type its option takes.
  ///
  /// The type has to come from the option rather than from the value, so that
  /// `exclude: ['a']` arrives as a `List<String>` (a bare `List<dynamic>` would
  /// not satisfy the option) and so that a mismatch is reported against the
  /// file, naming the key and what was expected.
  ///
  /// Three settings accept less than their type allows. Their rules live with
  /// the option — as `allowedValues`, a `customValidator`, a `min` — and are
  /// applied to whatever the command line provides; these readers hold the file
  /// to the same rules, from the same [formatNames] and [parseKinds], so that a
  /// bad value is reported against the file it is written in either way.
  Object? _typedValue(String key) => switch (_optionFor(key)) {
    CiachOption.format => _oneOf(key, formatNames),
    CiachOption.kinds => _kinds(key),
    CiachOption.concurrency => _positiveInt(key),
    final option => switch (option.option) {
      FlagOption() => _boolean(key),
      IntOption() => _positiveInt(key),
      MultiOption() => _strings(key),
      _ => _string(key),
    },
  };

  CiachOption<dynamic> _optionFor(String key) =>
      CiachOption.values.firstWhere((option) => option.configKey == key);

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

  /// A list of strings, also accepting a bare string as a one-element list
  /// (`exclude: test/**`).
  List<String>? _strings(String key) => switch (settings[key]) {
    null => null,
    final String value => [value],
    final Iterable<Object?> values => [
      for (final value in values)
        if (value is String) value else _wrong(key, 'a list of strings', value),
    ],
    final other => _wrong(key, 'a list of strings', other),
  };

  /// A string setting restricted to [allowed] values.
  String? _oneOf(String key, List<String> allowed) {
    final value = _string(key);
    if (value != null && !allowed.contains(value)) {
      throw FormatException(
        "$path: '$key' must be one of ${allowed.join(', ')}, got '$value'.",
      );
    }
    return value;
  }

  /// Declaration kind names, left for `parseKinds` to turn into symbol kinds
  /// but validated here, so an unknown kind names the file it came from.
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
