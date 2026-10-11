import 'package:collection/collection.dart';

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

  /// A service known only by the conventional `CI`, or `--ci` outside any.
  other('CI', 'CI');

  const CiRunner(this.label, this.variable);

  /// The service's name, for the log.
  final String label;

  /// The environment variable that identifies it.
  final String variable;

  /// The `--format` whose output this service turns into annotations, or
  /// `null` where plain text is the best there is.
  String? get annotationFormat => switch (this) {
    .githubActions => 'github',
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
