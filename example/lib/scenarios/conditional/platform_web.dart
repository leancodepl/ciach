// The variant picked on the web. Nothing resolves to it, so each public
// declaration shares the references of its namesake in platform_io.dart.

import 'package:sample_pkg/scenarios/conditional/web_label.dart';

// Used through its namesake -> NOT flagged.
bool get conditionalIsWeb => true;

// Its namesake is unused -> flagged, together with the namesake.
bool get conditionalDeadOnBoth => true;

// No namesake, and unused -> flagged.
void conditionalWebOnly() {}

class ConditionalPlatform {
  // Used through its namesake -> NOT flagged.
  String label() => webLabel();

  // Private, so no other library can use it -> flagged.
  void _unusedWebOnly() {}
}
