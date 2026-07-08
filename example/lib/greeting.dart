// Top-level functions, constants, and variables.
//
// The expected "unused" set is asserted by test/finder_test.dart. Keep this in
// sync with that test when editing.

/// Referenced from bin/app.dart -> USED.
void registerHandlers() {
  _internalHelper();
}

/// Referenced only by [registerHandlers] -> USED.
void _internalHelper() {}

/// Never referenced anywhere -> UNUSED (public function).
void danglingFunction() {}

/// Never referenced anywhere -> UNUSED (private function).
void _danglingPrivate() {}

/// Referenced from bin/app.dart -> USED.
const usedConstant = 'hello';

/// Never referenced anywhere -> UNUSED (public constant).
const unusedConstant = 'bye';

/// Incremented from bin/app.dart -> USED (mutable top-level variable).
int visitCount = 0;

/// Never referenced anywhere -> UNUSED (mutable top-level variable).
int staleCounter = 0;

/// Never called from real code -> UNUSED (private function). Its own doc
/// comment link to [_docOnlyMentioned] is the only "reference" that function
/// ever gets.
void _referencesOnlyInDocs() {}

/// Never called from real code, only named by the link above -> DOC-ONLY,
/// not UNUSED: the link counts as a reference, so a plain reference search
/// can't tell this apart from something genuinely called. Reported
/// separately, and never touched by --remove.
void _docOnlyMentioned() {}
