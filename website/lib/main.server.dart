/// Server entrypoint: runs once during `jaspr build` to pre-render every route.
library;

import 'package:ciach_website/app.dart';
import 'package:ciach_website/grammars/console_grammar.dart';
import 'package:ciach_website/main.server.options.dart';
import 'package:jaspr/server.dart';
import 'package:leancode_jaspr_ds/leancode_jaspr_ds.dart';
import 'package:leancode_jaspr_ds/server.dart';

Future<void> main() async {
  Jaspr.initializeApp(options: defaultServerOptions);
  await initHighlighting([console]);

  runApp(App(version: versionFromPubspec('ciach')));
}
