import 'package:collection/collection.dart';

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

  /// The service [environment] says the process runs on, or `null` for a
  /// local run. A variable counts as set when it is not empty, `false` or `0`.
  static CiRunner? detect(Map<String, String> environment) =>
      values.firstWhereOrNull((runner) => _isSet(environment[runner.variable]));

  static bool _isSet(String? value) => switch (value?.trim().toLowerCase()) {
    null || '' || 'false' || '0' => false,
    _ => true,
  };
}
