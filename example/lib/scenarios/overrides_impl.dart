// The override of `Valve.close` that lives outside overrides.dart, so a scan
// of that file alone cannot delete it; see lib/scenarios/overrides.dart.

import 'package:sample_pkg/scenarios/overrides.dart';

class Spigot implements Valve {
  @override
  void close() {}
}
