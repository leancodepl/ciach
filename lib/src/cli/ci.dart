import 'dart:io';

import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;

/// What a run on CI defaults to where nothing says otherwise: the one list the
/// option resolution and the verbose log both read.
typedef CiDefaults = ({
  bool setExitIfChanged,
  bool verbose,
  bool showProgress,
  String? format,
});

/// The CI service a run is on, told from the environment variable each one
/// sets, so the defaults can suit a runner rather than a terminal.
enum CiRunner {
  githubActions('GitHub Actions', 'GITHUB_ACTIONS'),
  gitlab('GitLab CI', 'GITLAB_CI'),
  circle('CircleCI', 'CIRCLECI'),
  travis('Travis CI', 'TRAVIS'),
  buildkite('Buildkite', 'BUILDKITE'),
  azurePipelines('Azure Pipelines', 'TF_BUILD'),
  jenkins('Jenkins', 'JENKINS_URL'),
  teamCity('TeamCity', 'TEAMCITY_VERSION'),
  codeBuild('AWS CodeBuild', 'CODEBUILD_BUILD_ID'),
  bitbucket('Bitbucket Pipelines', 'BITBUCKET_BUILD_NUMBER'),
  codemagic('Codemagic', 'CM_BUILD_ID'),

  /// A service known only by the conventional `CI`, or `--ci` outside any.
  other('CI', 'CI');

  const CiRunner(this.label, this.variable);

  /// The service's name, for the log.
  final String label;

  /// The environment variable that identifies it.
  final String variable;

  /// The defaults a run on this service changes: findings fail the run, the
  /// log explains it, the progress line stays off since a log keeps every
  /// overwrite, and the format is the one this service turns into annotations,
  /// where it has one.
  CiDefaults get defaults => (
    setExitIfChanged: true,
    verbose: true,
    showProgress: false,
    format: switch (this) {
      .githubActions => 'github',
      .azurePipelines => 'azure',
      .teamCity => 'teamcity',
      _ => null,
    },
  );

  /// The environment variable naming the directory this service checked the
  /// repository out to, where it sets one.
  String? get checkoutVariable => switch (this) {
    .githubActions => 'GITHUB_WORKSPACE',
    .gitlab => 'CI_PROJECT_DIR',
    .azurePipelines => 'BUILD_SOURCESDIRECTORY',
    _ => null,
  };

  /// The service [environment] says the process runs on, or `null` for a
  /// local run. A variable counts as set when it is not empty, `false` or `0`.
  static CiRunner? detect(Map<String, String> environment) =>
      values.firstWhereOrNull((runner) => _isSet(environment[runner.variable]));

  static bool _isSet(String? value) => switch (value?.trim().toLowerCase()) {
    null || '' || 'false' || '0' => false,
    _ => true,
  };
}

/// The repository root a CI service resolves report paths from, for a scan of
/// [scanRoot] in a checkout at [checkoutDir]: the outermost directory with a
/// `.git` from [scanRoot] up to [checkoutDir], so a submodule or a nested clone
/// still maps to the checked-out repository, or [checkoutDir] itself when none
/// has one. `null` when [checkoutDir] is unknown or does not hold [scanRoot].
String? checkoutRoot(String scanRoot, {required String? checkoutDir}) {
  if (checkoutDir == null || checkoutDir.isEmpty) {
    return null;
  }
  final checkout = p.normalize(p.absolute(checkoutDir));
  var dir = p.normalize(p.absolute(scanRoot));
  if (!p.equals(dir, checkout) && !p.isWithin(checkout, dir)) {
    return null;
  }
  String? outermost;
  while (true) {
    // A file in a submodule or worktree, a directory in a plain clone.
    if (FileSystemEntity.typeSync(p.join(dir, '.git')) != .notFound) {
      outermost = dir;
    }
    if (p.equals(dir, checkout)) {
      return outermost ?? checkout;
    }
    dir = p.dirname(dir);
  }
}
