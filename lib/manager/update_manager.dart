import 'package:cqut/api/api_service.dart';
import 'package:cqut/model/update_model.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateManager {
  static final UpdateManager _instance = UpdateManager._internal();
  factory UpdateManager() => _instance;
  UpdateManager._internal();

  final ApiService _apiService = ApiService();

  /// 检查更新
  /// [context] 用于显示弹窗
  /// [showNoUpdateToast] 是否在没有更新时显示提示（手动检查时为 true）
  Future<void> checkUpdate(BuildContext context, {bool showNoUpdateToast = false}) async {
    // 1. 获取当前版本
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String currentVersion = packageInfo.version;

    // 2. 获取远程版本
    UpdateModel? updateInfo = await _apiService.update.checkUpdate();

    if (updateInfo == null) {
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('检查更新失败，请稍后重试')),
        );
      }
      return;
    }

    // 3. 比较版本
    // 假设 tag_name 格式为 "v1.0.1" 或 "1.0.1"
    String remoteVersion = updateInfo.tagName.replaceAll('v', '');
    
    if (_hasNewVersion(currentVersion, remoteVersion)) {
      if (context.mounted) {
        _showUpdateDialog(context, updateInfo, currentVersion);
      }
    } else {
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('当前已是最新版本')),
        );
      }
    }
  }

  bool _hasNewVersion(String current, String remote) {
    try {
      List<int> currentParts = current.split('.').map(int.parse).toList();
      List<int> remoteParts = remote.split('.').map(int.parse).toList();

      for (int i = 0; i < remoteParts.length; i++) {
        int remotePart = remoteParts[i];
        int currentPart = (i < currentParts.length) ? currentParts[i] : 0;

        if (remotePart > currentPart) return true;
        if (remotePart < currentPart) return false;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  void _showUpdateDialog(BuildContext context, UpdateModel info, String currentVersion) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('发现新版本 ${info.tagName}'),
          content: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('当前版本: $currentVersion'),
                SizedBox(height: 8),
                Text('更新内容:', style: TextStyle(fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text(info.body),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('稍后'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.pop(context);
                _launchDownload(context, info.downloadUrl);
              },
              child: Text('立即更新'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchDownload(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法打开下载链接')),
        );
      }
    }
  }
}
