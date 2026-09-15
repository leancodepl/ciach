// Keeps `LiveHelpers` alive through a member, `ShownHelpers` through the
// `show`.
// ignore_for_file: unused_shown_name

import 'package:sample_pkg/scenarios/extensions_emptied.dart'
    show LiveHelpers, ShownHelpers, toMeters;

/// Reached from nothing -> UNUSED (function).
int useEmptiedExtensions() => 21.alive() + toMeters(1).value;
