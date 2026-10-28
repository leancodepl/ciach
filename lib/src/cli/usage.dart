/*
 * AI-Provenance:
 *   model: claude-fable-5-1
 *   harness: Claude Code
 *   plugins:
 *     - lean-ai-provenance
 *   skills:
 *     - mark-ai-provenance
 */

import 'package:args/args.dart';
import 'package:ciach/src/cli/args.dart';
import 'package:ciach/src/cli/option_values.dart';
import 'package:ciach/src/version.dart';

/// The full `--help` text, wrapping [parser]'s generated option list.
String usage(ArgParser parser) =>
    '''
ciach $ciachVersion

Find unused (never-referenced) declarations in a Dart/Flutter package.

Usage: ciach [options] [path]

  path   Package root to analyze (defaults to the current directory).

${parser.usage}

Declaration kinds (-k, --kinds):
${_wrapped(kindNames, indent: '  ')}

Config file:
  Every option above can also be set in $configFileName in the package root,
  keyed by its long name, plus `path` for the positional argument. The command
  line wins over the file; --no-config ignores the file; --verbose says which
  file was read and what it set.

  `entry-points` lives only there: declarations a tool calls from generated
  code, each a `name`, or an `annotation` class that also matches its
  subclasses, with an optional `glob` for the files it may live in.

    # $configFileName
    public: false
    exclude:
      - 'test/**'
    exported-packages: [packages/api]   # imported from outside the analysis
    entry-points:
      - name: bootstrap               # an isolate entry point
        glob: 'lib/src/isolate.dart'
      - name: MyHost.callback         # a member, called from native code
        glob: 'lib/my_host.dart'
      - annotation: Story             # what `@Story()` annotates
    kinds: [class, function]
    format: json

Ignore markers:
  A `// ciach:ignore` comment keeps the declaration on the next line, or the
  one named on its line when it trails code. `// ciach:ignore-start` and
  `// ciach:ignore-end` keep everything named between them, and
  `// ciach:ignore-file` keeps the whole file.

Examples:
  # Scan the current package
  ciach

  # Only private declarations, excluding tests, as JSON
  ciach --no-public -e 'test/**' -f json lib/

  # A monorepo package whose callers live in sibling packages
  ciach pkgs/core --analysis-root .

  # Read settings from a config file elsewhere
  ciach --config tool/ciach.yaml

  # Ignore the package's config file for one run
  ciach --no-config

  # In CI, --set-exit-if-changed and --verbose are on by default, and on GitHub
  # Actions each finding is an annotation; spelled out, the same works anywhere
  ciach -f github --set-exit-if-changed -v

  # Remove what's found, after confirming
  ciach --remove

  # Remove without asking (e.g. in a script)
  ciach --remove --force''';

/// [text] as [indent]-prefixed lines of at most [width] characters.
String _wrapped(String text, {String indent = '', int width = 76}) {
  final lines = <String>[];
  for (final word in text.split(' ')) {
    if (lines.isEmpty || '${lines.last} $word'.length > width) {
      lines.add('$indent$word');
    } else {
      lines[lines.length - 1] = '${lines.last} $word';
    }
  }
  return lines.join('\n');
}
