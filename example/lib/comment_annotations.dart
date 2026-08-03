// @override vm:entry-point

void deadAfterHeaderBlock() {}

/// @override
void deadOverrideInDoc() {}

/// vm:entry-point
void deadEntryPointInDoc() {}

void deadOverrideTrailing() {} // @override

void deadEntryPointTrailing() {} // vm:entry-point

// @override

void deadOverrideBlankSeparated() {}

// vm:entry-point

void deadEntryPointBlankSeparated() {}

/*
@override
*/
void deadOverrideBareBlock() {}

/*
vm:entry-point
*/
void deadEntryPointBareBlock() {}

@pragma('vm:entry-point')
void liveByRealPragma() {}
