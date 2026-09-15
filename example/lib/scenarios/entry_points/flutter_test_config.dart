// Right file: the bootstrap calls `testExecutable` whatever its shape, so it
// is exempt. Expected findings: `deadHelperNextToConfig` only.

Future<void> testExecutable(int retries) async {}

void deadHelperNextToConfig() {}
