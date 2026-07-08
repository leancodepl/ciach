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
