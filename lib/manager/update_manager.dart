import 'package:cqut/api/api_service.dart';
import 'package:cqut/model/update_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdateManager {
  static final UpdateManager _instance = UpdateManager._internal();
  factory UpdateManager() => _instance;
  UpdateManager._internal();

  final ApiService _apiService = ApiService();

  String _formatReleaseNotes(String raw) {
    final normalized = raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = normalized.split('\n');
    final buffer = StringBuffer();
    for (int i = 0; i < lines.length; i++) {
      final line = lines[i];
      if (line.isNotEmpty && !line.endsWith('  ')) {
        buffer.write(line);
        buffer.write('  ');
      } else {
        buffer.write(line);
      }
      if (i != lines.length - 1) buffer.write('\n');
    }
    return buffer.toString();
  }

  /// 检查更新
  /// [context] 用于显示弹窗
  /// [showNoUpdateToast] 是否在没有更新时显示提示（手动检查时为 true）
  Future<void> checkUpdate(
    BuildContext context, {
    bool showNoUpdateToast = false,
  }) async {
    // 1. 获取当前版本
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    String currentVersion = packageInfo.version;

    // 2. 获取远程版本
    UpdateModel? updateInfo = await _apiService.update.checkUpdate();

    if (updateInfo == null) {
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('检查更新失败，请稍后重试')));
      }
      return;
    }

    String remoteVersion = updateInfo.tagName.replaceAll('v', '');

    if (_hasNewVersion(currentVersion, remoteVersion)) {
      if (context.mounted) {
        _showUpdateDialog(context, updateInfo, currentVersion);
      }
    } else {
      if (showNoUpdateToast && context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('当前已是最新版本')));
      }
    }
  }

  bool _hasNewVersion(String current, String remote) {
    try {
      List<String> currentChunks = current.split('-');
      List<String> remoteChunks = remote.split('-');
      List<int> currentParts = currentChunks.first
          .split('.')
          .map(int.parse)
          .toList();
      List<int> remoteParts = remoteChunks.first
          .split('.')
          .map(int.parse)
          .toList();
      String currentSuffix = currentChunks.length > 1
          ? currentChunks.sublist(1).join('-')
          : '';
      String remoteSuffix = remoteChunks.length > 1
          ? remoteChunks.sublist(1).join('-')
          : '';

      int maxLen = currentParts.length > remoteParts.length
          ? currentParts.length
          : remoteParts.length;
      for (int i = 0; i < maxLen; i++) {
        int remotePart = (i < remoteParts.length) ? remoteParts[i] : 0;
        int currentPart = (i < currentParts.length) ? currentParts[i] : 0;

        if (remotePart > currentPart) return true;
        if (remotePart < currentPart) return false;
      }
      if (currentSuffix == remoteSuffix) return false;
      if (currentSuffix.isEmpty && remoteSuffix.isNotEmpty) return true;
      if (currentSuffix.isNotEmpty && remoteSuffix.isEmpty) return false;
      return remoteSuffix.compareTo(currentSuffix) > 0;
    } catch (e) {
      return false;
    }
  }

  void _showUpdateDialog(
    BuildContext context,
    UpdateModel info,
    String currentVersion,
  ) {
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
                MarkdownBody(
                  data: _formatReleaseNotes(info.body),
                  styleSheet: MarkdownStyleSheet.fromTheme(Theme.of(context)),
                  onTapLink: (text, href, title) {
                    if (href == null || href.isEmpty) return;
                    _launchExternalUrl(context, href);
                  },
                ),
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
                _launchExternalUrl(context, info.downloadUrl);
              },
              child: Text('立即更新'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _launchExternalUrl(BuildContext context, String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('无法打开链接')));
      }
    }
  }
}
