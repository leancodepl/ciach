// Provides the context-typed API a dot-shorthand resolves against, plus one
// normal reference that keeps XrefEvent.signIn used.

import 'package:sample_pkg/xref_event.dart';

class XrefAnalytics {
  void logEvent(XrefEvent event) => print(event);
}

const XrefEvent xrefControl = XrefEvent.signIn;
