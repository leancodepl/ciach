// Conditional-import fixture. Expected findings are asserted by
// test/finder_test.dart; keep in sync.

export 'barrel_io.dart' if (dart.library.js_interop) 'barrel_web.dart';
export 'platform_io.dart' if (dart.library.js_interop) 'platform_web.dart';
