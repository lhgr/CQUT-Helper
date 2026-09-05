import 'dart:io';

import 'package:cqut_helper/utils/android_background_restrictions.dart';
import 'package:flutter/material.dart';

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
    } catch (_) {
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
        _error = '无法打开系统设置，请重试，或稍后在手机设置中手动允许应用后台运行和自启动。';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final content = switch (_step) {
      _SetupStep.battery => '先打开省电策略，允许应用忽略电池优化或选择“不限制”。设置后请返回本应用，继续设置自启动。',
      _SetupStep.autoStart =>
        '接下来请打开自启动设置，允许 CQUT Helper 自启动。若进入应用详情，请在其中查找自启动或后台运行设置。设置后请返回本应用。',
      _SetupStep.finish =>
        '请确认已在系统设置中允许自启动和后台运行。应用无法直接确认自启动开关状态，后续可在“同步与诊断”中查看后台运行情况。',
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
