import 'package:cqut_helper/utils/ios_release.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

const iosPrereleaseNoticeAcknowledgedKey = 'ios_prerelease_notice_acknowledged';

Future<void> showIosPrereleaseNotice(
  BuildContext context, {
  IosReleaseInfo release = currentIosRelease,
}) async {
  if (kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS ||
      !release.isPrerelease) {
    return;
  }

  final prefs = await SharedPreferences.getInstance();
  if (prefs.getBool(iosPrereleaseNoticeAcknowledgedKey) == true ||
      !context.mounted) {
    return;
  }

  var acknowledging = false;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) => PopScope(
      canPop: false,
      child: AlertDialog(
        title: Text('${release.label} 测试版本'),
        content: Text('当前为 iOS ${release.label} 测试版本，部分功能可能尚不完善，使用过程中可能出现异常。'),
        actions: [
          FilledButton(
            onPressed: () async {
              if (acknowledging) return;
              acknowledging = true;
              await prefs.setBool(iosPrereleaseNoticeAcknowledgedKey, true);
              if (dialogContext.mounted) Navigator.of(dialogContext).pop();
            },
            child: const Text('我知道了'),
          ),
        ],
      ),
    ),
  );
}
