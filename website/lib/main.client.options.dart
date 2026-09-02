// dart format off
// ignore_for_file: type=lint

// GENERATED FILE, DO NOT MODIFY
// Generated with jaspr_builder

import 'package:jaspr/client.dart';

import 'package:ciach_website/components/copy_button.dart'
    deferred as _copy_button;

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
    'copy_button': ClientLoader(
      (p) => _copy_button.CopyButton(
        text: p['text'] as String,
        label: p['label'] as String?,
      ),
      loader: _copy_button.loadLibrary,
    ),
  },
);
