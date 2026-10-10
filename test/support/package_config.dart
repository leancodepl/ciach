import 'dart:convert';

import 'package:path/path.dart' as p;

/// A `package_config.json` as `pub get` writes it to `<package>/.dart_tool/`:
/// [roots] maps each package to its root, relative to `<package>`.
String packageConfig(Map<String, String> roots) =>
    const JsonEncoder.withIndent('  ').convert({
      'configVersion': 2,
      'packages': [
        for (final MapEntry(key: name, value: root) in roots.entries)
          {
            'name': name,
            'rootUri': '${p.url.normalize(p.url.join('..', root))}/',
            'packageUri': 'lib/',
            'languageVersion': '3.10',
          },
      ],
    });
