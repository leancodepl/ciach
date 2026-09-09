// The uses side of extensions_emptied.dart: calls one member of `LiveHelpers`
// (keeping that extension alive through its member, not its name) and names
// `ShownHelpers` in a `show` (keeping the extension, but not its member).

// ignore_for_file: unused_shown_name, the `show` is the point

import 'package:sample_pkg/scenarios/extensions_emptied.dart'
    show LiveHelpers, ShownHelpers, toMeters;

/// Reached from nothing in the scan -> UNUSED (function); it exists to hold the
/// references above.
int useEmptiedExtensions() => 21.alive() + toMeters(1).value;
