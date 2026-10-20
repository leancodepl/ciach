// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:leancode_site/src/components/copy_button.dart'
    deferred as _copy_button;
import 'package:leancode_site/src/components/demo_trigger.dart'
    deferred as _demo_trigger;
import 'package:leancode_site/src/components/docs_toc.dart'
    deferred as _docs_toc;
import 'package:leancode_site/src/icons.dart' as _icons;

/// Default [ClientOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.client.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultClientOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ClientOptions get defaultClientOptions => ClientOptions(
  clients: {
    'leancode_site:copy_button': ClientLoader(
      (p) => _copy_button.CopyButton(
        text: p.get<String>('text'),
        label: p.get<String?>('label'),
        title: p.get<String>('title'),
        icon: _icons.Icon.fromJson(p.get<List<String>>('icon')),
      ),
      loader: _copy_button.loadLibrary,
    ),
    'leancode_site:demo_trigger': ClientLoader(
      (p) => _demo_trigger.DemoTrigger(targetId: p.get<String>('targetId')),
      loader: _demo_trigger.loadLibrary,
    ),
    'leancode_site:docs_toc': ClientLoader(
      (p) => _docs_toc.DocsToc(
        path: p.get<String>('path'),
        ids: p.get<List<Object?>>('ids').cast<String>(),
        labels: p.get<List<Object?>>('labels').cast<String>(),
      ),
      loader: _docs_toc.loadLibrary,
    ),
  },
);
