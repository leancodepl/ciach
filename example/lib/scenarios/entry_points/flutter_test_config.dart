// Right file, wrong signature: the bootstrap could not call this. Expected
// findings: both declarations.

Future<void> testExecutable(int retries) async {}

void deadHelperNextToConfig() {}
