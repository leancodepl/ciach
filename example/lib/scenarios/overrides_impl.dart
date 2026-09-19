// The `Valve.close` override in a second file, so a scan of overrides.dart
// alone cannot delete it.

import 'package:sample_pkg/scenarios/overrides.dart';

class Spigot implements Valve {
  @override
  void close() {}
}
