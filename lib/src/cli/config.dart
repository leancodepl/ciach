import 'dart:io';

import 'package:ciach/src/cli/args.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:yaml/yaml.dart';

/// File names looked for, in order, when discovering a config file in the
/// project directory.
const configFileNames = ['ciach.yaml', 'ciach.yml'];

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
  'concurrency',
  'dart',
};

/// A config file's contents, with one nullable field per setting.
///
/// `null` means "not set here", which is what lets the command line and the
/// built-in defaults show through — see `resolveOptions`.
class CiachConfig {
  /// Creates a config with only the given settings present.
  const CiachConfig({
    this.path,
    this.public,
    this.generated,
    this.overrides,
    this.operators,
    this.unusedUnionMembers,
    this.reportToJson,
    this.setExitIfChanged,
    this.remove,
    this.force,
    this.exclude,
    this.include,
    this.generatedSuffix,
    this.kinds,
    this.format,
    this.color,
    this.progress,
    this.concurrency,
    this.dart,
  });

  /// Parses [source] as a ciach config file.
  ///
  /// [origin] names the source in error messages (typically the file path).
  /// Throws a [FormatException] describing the offending key on a malformed
  /// document, an unknown key, or a value of the wrong type.
  factory CiachConfig.parse(String source, {required String origin}) {
    final Object? document;
    try {
      document = loadYaml(source, sourceUrl: Uri.file(origin));
    } on YamlException catch (e) {
      throw FormatException('$origin: not valid YAML: ${e.message}');
    }

    // An empty file parses to null; treat it as "no settings", not an error.
    if (document == null) {
      return const CiachConfig();
    }
    if (document is! Map) {
      throw FormatException('$origin: the top level must be a map of options.');
    }

    final unknown = document.keys
        .map((k) => '$k')
        .where((k) => !configKeys.contains(k))
        .toList();
    if (unknown.isNotEmpty) {
      final valid = (configKeys.toList()..sort()).join(', ');
      throw FormatException(
        '$origin: unknown option${unknown.length == 1 ? '' : 's'} '
        "${unknown.map((k) => "'$k'").join(', ')}. Valid options: $valid.",
      );
    }

    final reader = _ConfigReader(document, origin);
    return CiachConfig(
      path: reader.string('path'),
      public: reader.boolean('public'),
      generated: reader.boolean('generated'),
      overrides: reader.boolean('overrides'),
      operators: reader.boolean('operators'),
      unusedUnionMembers: reader.boolean('unused-union-members'),
      reportToJson: reader.boolean('report-tojson'),
      setExitIfChanged: reader.boolean('set-exit-if-changed'),
      remove: reader.boolean('remove'),
      force: reader.boolean('force'),
      exclude: reader.strings('exclude'),
      include: reader.strings('include'),
      generatedSuffix: reader.strings('generated-suffix'),
      kinds: reader.kinds('kinds'),
      format: reader.oneOf('format', formatNames),
      color: reader.boolean('color'),
      progress: reader.boolean('progress'),
      concurrency: reader.positiveInt('concurrency'),
      dart: reader.string('dart'),
    );
  }

  /// Package root to analyze, mirroring the positional `path` argument.
  final String? path;

  /// Mirrors `--[no-]public`.
  final bool? public;

  /// Mirrors `--[no-]generated`.
  final bool? generated;

  /// Mirrors `--[no-]overrides`.
  final bool? overrides;

  /// Mirrors `--[no-]operators`.
  final bool? operators;

  /// Mirrors `--[no-]unused-union-members`.
  final bool? unusedUnionMembers;

  /// Mirrors `--[no-]report-tojson`.
  final bool? reportToJson;

  /// Mirrors `--set-exit-if-changed`.
  final bool? setExitIfChanged;

  /// Mirrors `--remove`.
  final bool? remove;

  /// Mirrors `--force`.
  final bool? force;

  /// Mirrors `--exclude`; a single string is accepted as a one-element list.
  final List<String>? exclude;

  /// Mirrors `--include`; a single string is accepted as a one-element list.
  final List<String>? include;

  /// Mirrors `--generated-suffix`.
  final List<String>? generatedSuffix;

  /// Mirrors `--kinds`, unparsed. Either a list of kind names or a single
  /// comma-separated string; `parseKinds` accepts both shapes.
  final List<String>? kinds;

  /// Mirrors `--format`.
  final String? format;

  /// Mirrors `--[no-]color`.
  final bool? color;

  /// Mirrors `--[no-]progress`.
  final bool? progress;

  /// Mirrors `--concurrency`.
  final int? concurrency;

  /// Mirrors `--dart`.
  final String? dart;
}

/// A config file that was loaded, together with where it came from.
typedef LoadedConfig = ({CiachConfig config, String? path});

/// Resolves and loads the config file for a run.
///
/// Returns an empty config (and a `null` path) when [ignore] is set or when no
/// config file is found. [explicitPath] — from `--config` — is loaded as-is;
/// otherwise [configFileNames] are looked for in [projectDir].
///
/// Throws a [FormatException] when [explicitPath] does not exist or when the
/// file cannot be parsed.
LoadedConfig loadConfig({
  required String projectDir,
  String? explicitPath,
  bool ignore = false,
}) {
  if (ignore) {
    return (config: const CiachConfig(), path: null);
  }

  final File file;
  if (explicitPath != null) {
    file = File(explicitPath);
    if (!file.existsSync()) {
      throw FormatException('Config file does not exist: $explicitPath');
    }
  } else {
    final found = configFileNames
        .map((name) => File(p.join(projectDir, name)))
        .where((f) => f.existsSync())
        .firstOrNull;
    if (found == null) {
      return (config: const CiachConfig(), path: null);
    }
    file = found;
  }

  final String source;
  try {
    source = file.readAsStringSync();
  } on FileSystemException catch (e) {
    throw FormatException('Cannot read config file ${file.path}: ${e.message}');
  }

  return (
    config: CiachConfig.parse(source, origin: file.path),
    path: file.path,
  );
}

/// Reads typed values out of a parsed YAML map, naming the config file and the
/// offending key on every type mismatch.
class _ConfigReader {
  _ConfigReader(this._map, this._origin);

  final Map<Object?, Object?> _map;
  final String _origin;

  Never _wrong(String key, String expected, Object? value) =>
      throw FormatException(
        "$_origin: '$key' must be $expected, got ${_describe(value)}.",
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

  /// The raw value for [key], or `null` when the key is absent. A key present
  /// with an empty value (`public:`) counts as absent, so commenting a value
  /// out behaves like deleting the line.
  Object? _raw(String key) => _map[key];

  bool? boolean(String key) => switch (_raw(key)) {
    null => null,
    final bool value => value,
    final other => _wrong(key, 'true or false', other),
  };

  String? string(String key) => switch (_raw(key)) {
    null => null,
    final String value => value,
    final other => _wrong(key, 'a string', other),
  };

  String? oneOf(String key, List<String> allowed) {
    final value = string(key);
    if (value != null && !allowed.contains(value)) {
      throw FormatException(
        "$_origin: '$key' must be one of ${allowed.join(', ')}, got '$value'.",
      );
    }
    return value;
  }

  /// A list of strings, also accepting a single string as a one-element list
  /// (`exclude: test/**`).
  List<String>? strings(String key) => switch (_raw(key)) {
    null => null,
    final String value => [value],
    final Iterable<Object?> values => [
      for (final value in values)
        if (value is String) value else _wrong(key, 'a list of strings', value),
    ],
    final other => _wrong(key, 'a list of strings', other),
  };

  /// Declaration kind names, left unparsed for `parseKinds` to turn into
  /// symbol kinds, but validated here so an unknown kind names the file it
  /// came from.
  List<String>? kinds(String key) {
    final values = strings(key);
    if (values != null) {
      try {
        parseKinds(values);
      } on FormatException catch (e) {
        throw FormatException("$_origin: '$key': ${e.message}");
      }
    }
    return values;
  }

  int? positiveInt(String key) => switch (_raw(key)) {
    null => null,
    final int value when value > 0 => value,
    final other => _wrong(key, 'a positive integer', other),
  };
}
