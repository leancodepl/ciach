// File header mentioning an @override hook and a vm:entry-point pragma, so it
// must not skip the first declaration below. Asserted by test/finder_test.dart.

/// First declaration; only the header block above mentions the annotations.
void deadAfterHeaderBlock() {}

/// Mentions @override.
void deadOverrideInDoc() {}

/// Mentions a vm:entry-point pragma.
void deadEntryPointInDoc() {}

void deadOverrideTrailing() {} // @override

void deadEntryPointTrailing() {} // vm:entry-point

// Mentions @override, a blank line above the declaration.

void deadOverrideBlankSeparated() {}

// Mentions vm:entry-point, a blank line above the declaration.

void deadEntryPointBlankSeparated() {}

/*
@override on an unprefixed block-comment line
*/
void deadOverrideBareBlock() {}

/*
vm:entry-point on an unprefixed block-comment line
*/
void deadEntryPointBareBlock() {}

// Real pragma inside a string literal -> survives stripping, stays skipped.
@pragma('vm:entry-point')
void liveByRealPragma() {}
