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

/// Referenced from bin/app.dart -> USED, though it also calls itself.
int factorial(int n) => n <= 1 ? 1 : n * factorial(n - 1);

/// Calls only itself -> UNUSED (private function). The recursive call sits in
/// its own body, which goes when the function does, so it is no use.
int _countdown(int n) => n == 0 ? 0 : _countdown(n - 1);

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
