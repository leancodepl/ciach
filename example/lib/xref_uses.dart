// Deliberately does NOT import xref_event.dart; the reference below still
// resolves without it.

import 'package:sample_pkg/xref_analytics.dart';
import 'package:sample_pkg/xref_shapes.dart';

String describeShape(XrefState state) => switch (state) {
  XrefLoadedState(hasActive: true, ready: true) => 'both',
  _ => 'other',
};

class Emitter {
  Emitter(this._analytics);
  final XrefAnalytics _analytics;

  void signOut() => _analytics.logEvent(.signOut);
}
