import 'dart:io';

import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:material_ui/material_ui.dart';

Future<bool> showNoticeEnhancementConsentDialog(
  BuildContext context, {
  required bool isIOS,
}) async {
  final timing = isIOS ? '应用会在启动、返回前台和手动同步时检查调课通知。' : '应用会定期在后台检查调课通知。';
  final permissions = isIOS ? '继续后会申请通知权限。' : '继续后会申请通知权限，并引导你设置电池优化和自启动。';
  return await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          scrollable: true,
          title: const Text('开启“调课通知增强”'),
          content: Text(
            '$timing'
            '发现变更后会更新受影响的教学周。\n\n'
            '查询时会向所选服务发送学号、统一认证加密密码和当前学期。风险说明见“设置 → 教务查询服务”。\n\n'
            '$permissions',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('保持关闭'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('我已了解，继续'),
            ),
          ],
        ),
      ) ??
      false;
}

Future<bool> showBackgroundPollingSetupDialog(BuildContext context) async {
  if (!Platform.isAndroid) return true;
  final ignored =
      await AndroidBackgroundRestrictions.isIgnoringBatteryOptimizations();
  if (!context.mounted) return false;
  return await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => BackgroundPollingSetupDialog(
          batteryAlreadyIgnored: ignored == true,
        ),
      ) ??
      false;
}

class BackgroundPollingSetupDialog extends StatefulWidget {
  const BackgroundPollingSetupDialog({
    super.key,
    required this.batteryAlreadyIgnored,
    this.requestBattery =
        AndroidBackgroundRestrictions.requestIgnoreBatteryOptimizations,
    this.openBattery =
        AndroidBackgroundRestrictions.openBatteryOptimizationSettings,
    this.openAutoStart = AndroidBackgroundRestrictions.openAutoStartSettings,
  });

  final bool batteryAlreadyIgnored;
  final Future<bool> Function() requestBattery;
  final Future<bool> Function() openBattery;
  final Future<bool> Function() openAutoStart;

  @override
  State<BackgroundPollingSetupDialog> createState() =>
      _BackgroundPollingSetupDialogState();
}

enum _SetupStep { battery, autoStart, finish }

class _BackgroundPollingSetupDialogState
    extends State<BackgroundPollingSetupDialog> {
  late _SetupStep _step = widget.batteryAlreadyIgnored
      ? _SetupStep.autoStart
      : _SetupStep.battery;
  bool _opening = false;
  String? _error;

  Future<void> _openSettings() async {
    if (_opening) return;
    setState(() {
      _opening = true;
      _error = null;
    });
    var opened = false;
    try {
      opened = _step == _SetupStep.battery
          ? await widget.requestBattery() || await widget.openBattery()
          : await widget.openAutoStart();
    } catch (error, stackTrace) {
      AppLogger.I.logOperationFailure(
        'BackgroundPollingSetup',
        'open platform settings failed',
        error: error,
        stackTrace: stackTrace,
      );
      opened = false;
    }
    if (!mounted) return;
    setState(() {
      _opening = false;
      if (opened) {
        // The platform call only confirms launch. Keep this dialog open so
        // the next launch requires a user tap after returning to the app.
        _step = _step == _SetupStep.battery
            ? _SetupStep.autoStart
            : _SetupStep.finish;
      } else {
        _error = '无法打开系统设置，请重试，或在手机设置中手动允许后台运行和自启动。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_step) {
      _SetupStep.battery => '允许应用在后台运行（忽略电池优化或选择“不限制”）。完成后返回此处继续设置自启动。',
      _SetupStep.autoStart =>
        '允许 CQUT Helper 自启动。部分设备需在应用详情中开启自启动或后台运行。完成后返回此处。',
      _SetupStep.finish => '请确认已允许自启动和后台运行。系统无法直接读取自启动状态，可在“同步与修复”查看后台运行情况。',
    };
    return PopScope(
      canPop: !_opening,
      child: AlertDialog(
        title: Text(switch (_step) {
          _SetupStep.battery => '1. 设置省电策略',
          _SetupStep.autoStart => '2. 设置自启动',
          _SetupStep.finish => '后台运行设置',
        }),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(content),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
        actions: [
          if (_step != _SetupStep.finish)
            TextButton(
              onPressed: _opening
                  ? null
                  : () {
                      if (_step == _SetupStep.battery) {
                        setState(() {
                          _step = _SetupStep.autoStart;
                          _error = null;
                        });
                      } else {
                        Navigator.pop(context, true);
                      }
                    },
              child: const Text('稍后设置'),
            ),
          FilledButton(
            onPressed: _opening
                ? null
                : _step == _SetupStep.finish
                ? () => Navigator.pop(context, true)
                : _openSettings,
            child: Text(switch (_step) {
              _SetupStep.battery => '打开省电设置',
              _SetupStep.autoStart => '打开自启动设置',
              _SetupStep.finish => '完成',
            }),
          ),
        ],
      ),
    );
  }
}
