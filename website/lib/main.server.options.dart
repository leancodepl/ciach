// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/server.dart';
import 'package:ciach_website/components/copy_button.dart' as _copy_button;
import 'package:ciach_website/components/docs_toc.dart' as _docs_toc;

/// Default [ServerOptions] for use with your Jaspr project.
///
/// Use this to initialize Jaspr **before** calling [runApp].
///
/// Example:
/// ```dart
/// import 'main.server.options.dart';
///
/// void main() {
///   Jaspr.initializeApp(
///     options: defaultServerOptions,
///   );
///
///   runApp(...);
/// }
/// ```
ServerOptions get defaultServerOptions => ServerOptions(
  clientId: 'main.client.dart.js',
  clients: {
    _copy_button.CopyButton: ClientTarget<_copy_button.CopyButton>(
      'copy_button',
      params: __copy_buttonCopyButton,
    ),
    _docs_toc.DocsToc: ClientTarget<_docs_toc.DocsToc>(
      'docs_toc',
      params: __docs_tocDocsToc,
    ),
  },
);

Map<String, Object?> __copy_buttonCopyButton(_copy_button.CopyButton c) => {
  'text': c.text,
  'label': c.label,
};
Map<String, Object?> __docs_tocDocsToc(_docs_toc.DocsToc c) => {
  'path': c.path,
  'ids': c.ids,
  'labels': c.labels,
};
