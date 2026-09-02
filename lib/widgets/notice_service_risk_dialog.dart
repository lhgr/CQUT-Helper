import 'package:cqut_helper/manager/schedule_settings_manager.dart';
import 'package:flutter/material.dart';

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
            title: const Text('自定义调课服务风险提示'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '你正在使用自定义调课服务。应用会将你的学号、教务系统加密密码和当前学期发送至该地址；其安全性、数据使用及储存方式由服务提供者负责。请仅使用你信任的 HTTPS 服务。',
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  title: const Text('不再提示'),
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
