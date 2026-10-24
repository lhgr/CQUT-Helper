import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:material_ui/material_ui.dart';

Future<bool> confirmCustomNoticeServiceRisk(BuildContext context) async {
  if (!await ScheduleSettingsManager.shouldShowCustomServiceRiskWarning()) {
    return true;
  }
  if (!context.mounted) return false;

  var doNotShowAgain = false;
  final confirmed =
      await showDialog<bool>(
        context: context,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: const Text('使用自定义调课服务'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '应用会将你的学号、教务系统加密密码和当前学期发送至该地址，用于查询调课通知。数据安全和处理方式由服务提供者决定，请仅使用你信任的 HTTPS 服务。',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('以后不再提示'),
                  value: doNotShowAgain,
                  onChanged: (value) {
                    setDialogState(() => doNotShowAgain = value ?? false);
                  },
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('我已了解，继续'),
              ),
            ],
          ),
        ),
      ) ??
      false;

  if (confirmed && doNotShowAgain) {
    await ScheduleSettingsManager.suppressCustomServiceRiskWarning();
  }
  return confirmed;
}
