// Copyright (c) 2026 Example. A file header / license block for the whole file.
// Historically this file wired up an @override hook and a vm:entry-point pragma,
// so the header itself mentions both -- yet it must not skip any declaration.
//
// The expected results are asserted by test/finder_test.dart. Keep in sync.

/// First declaration in the file: the header block above mentions @override and
/// vm:entry-point, but neither may skip it -> reported UNUSED.
void deadAfterHeaderBlock() {}

/// Dead, and this doc comment merely mentions @override -> reported UNUSED.
void deadOverrideInDoc() {}

/// Dead, and this doc comment merely mentions a vm:entry-point pragma ->
/// reported UNUSED.
void deadEntryPointInDoc() {}

void deadOverrideTrailing() {} // formerly an @override hook

void deadEntryPointTrailing() {} // formerly a vm:entry-point pragma

// A stray note mentioning @override, separated from the declaration by a blank.

void deadOverrideBlankSeparated() {}

// A stray note mentioning vm:entry-point, separated from it by a blank line.

void deadEntryPointBlankSeparated() {}

/// A real pragma: the annotation lives inside a string literal, which survives
/// comment-stripping, so this stays skipped (never reported).
@pragma('vm:entry-point')
void liveByRealPragma() {}
