enum IosReleaseStage { alpha, beta, stable }

class IosReleaseInfo {
  const IosReleaseInfo(this.stage);

  final IosReleaseStage stage;

  bool get isPrerelease => stage != IosReleaseStage.stable;

  String? get label => switch (stage) {
    IosReleaseStage.alpha => 'Alpha',
    IosReleaseStage.beta => 'Beta',
    IosReleaseStage.stable => null,
  };

  String displayVersion(String version) =>
      isPrerelease ? '$version-${stage.name}' : version;

  String ipaFileName(String version) =>
      'CQUT-Helper-${displayVersion(version)}-unsigned.ipa';
}

const currentIosRelease = IosReleaseInfo(IosReleaseStage.alpha);
