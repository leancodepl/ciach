import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Writes the [files] of a package named `app` under [root], by their paths
/// relative to [root], with its `package_config.json`.
void writeAppPackage(String root, Map<String, String> files) {
  for (final MapEntry(key: path, value: source) in {
    '.dart_tool/package_config.json': packageConfig({'app': '.'}),
    ...files,
  }.entries) {
    File(p.join(root, path))
      ..createSync(recursive: true)
      ..writeAsStringSync(source);
  }
}

/// A `package_config.json` as `pub get` writes it to `<package>/.dart_tool/`:
/// [roots] maps each package to its root, relative to `<package>`. A package
/// has the Dart language version that [languageVersions] gives it, or else
/// 3.10.
String packageConfig(
  Map<String, String> roots, {
  Map<String, String> languageVersions = const {},
}) => const JsonEncoder.withIndent('  ').convert({
  'configVersion': 2,
  'packages': [
    for (final MapEntry(key: name, value: root) in roots.entries)
      {
        'name': name,
        'rootUri': '${p.url.normalize(p.url.join('..', root))}/',
        'packageUri': 'lib/',
        'languageVersion': languageVersions[name] ?? '3.10',
      },
  ],
});
