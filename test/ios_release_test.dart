import 'package:cqut_helper/utils/ios_release.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('iOS 阶段统一应用版本与 IPA 文件名', () {
    const alpha = IosReleaseInfo(IosReleaseStage.alpha);
    const beta = IosReleaseInfo(IosReleaseStage.beta);
    const stable = IosReleaseInfo(IosReleaseStage.stable);

    expect(alpha.displayVersion('1.2.1'), '1.2.1-alpha');
    expect(alpha.ipaFileName('1.2.1'), 'CQUT-Helper-1.2.1-alpha-unsigned.ipa');
    expect(alpha.label, 'Alpha');
    expect(alpha.isPrerelease, isTrue);
    expect(beta.displayVersion('1.2.1'), '1.2.1-beta');
    expect(beta.ipaFileName('1.2.1'), 'CQUT-Helper-1.2.1-beta-unsigned.ipa');
    expect(beta.label, 'Beta');
    expect(beta.isPrerelease, isTrue);
    expect(stable.displayVersion('1.2.1'), '1.2.1');
    expect(stable.ipaFileName('1.2.1'), 'CQUT-Helper-1.2.1-unsigned.ipa');
    expect(stable.label, isNull);
    expect(stable.isPrerelease, isFalse);
    expect(currentIosRelease.stage, IosReleaseStage.alpha);
  });
}
