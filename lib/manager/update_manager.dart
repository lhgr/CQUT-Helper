import 'package:flutter/foundation.dart';
import 'package:cqut_helper/api/api_service.dart';
import 'package:cqut_helper/api/update/update_api.dart';
import 'package:cqut_helper/model/update_model.dart';
import 'package:cqut_helper/widgets/release_notes_markdown.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:cqut_helper/utils/github_proxy.dart';

class UpdateManager {
  static final UpdateManager _instance = UpdateManager._internal();
  factory UpdateManager() => _instance;
  UpdateManager._internal();

  @visibleForTesting
  UpdateManager.forTesting({
    required this._fetchLatest,
    required this._currentVersion,
  });

  Future<UpdateFetchResult> Function({bool forceRefresh})? _fetchLatest;
  Future<String> Function()? _currentVersion;
  final Set<String> _shownVersions = <String>{};

  Future<UpdateFetchResult> fetchUpdate({bool forceRefresh = false}) {
    return (_fetchLatest ?? ApiService().update.fetchLatest)(
      forceRefresh: forceRefresh,
    );
  }

  /// Manual checks refresh the network and finish when the dialog closes.
  Future<void> checkUpdate(
    BuildContext context, {
    bool showNoUpdateToast = false,
  }) async {
    final result = await fetchUpdate(forceRefresh: showNoUpdateToast);
    if (!context.mounted) return;
    await showFetchedUpdate(context, result, manual: showNoUpdateToast);
  }

  /// False retains the startup result until its page can show a dialog.
  Future<bool> showFetchedUpdate(
    BuildContext context,
    UpdateFetchResult result, {
    bool manual = false,
    bool Function()? canShow,
  }) async {
    bool canPresent() =>
        context.mounted &&
        (WidgetsBinding.instance.lifecycleState == null ||
            WidgetsBinding.instance.lifecycleState ==
                AppLifecycleState.resumed) &&
        (ModalRoute.isCurrentOf(context) ?? true) &&
        (canShow?.call() ?? true);

    if (!canPresent()) return false;
    final info = result.info;
    if (info == null) {
      if (manual) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('检查更新失败，请稍后重试')));
      }
      return true;
    }
    if (!manual &&
        (result.failure != null || _shownVersions.contains(info.tagName))) {
      return true;
    }
    final currentVersion =
        await (_currentVersion?.call() ??
            PackageInfo.fromPlatform().then((info) => info.version));
    if (!context.mounted || !canPresent()) return false;
    final isNewVersion = _hasNewVersion(
      currentVersion,
      info.tagName.replaceAll('v', ''),
    );
    if (!manual && (!isNewVersion || _shownVersions.contains(info.tagName))) {
      return true;
    }
    _shownVersions.add(info.tagName);
    await _showVersionDialog(
      context,
      info,
      currentVersion,
      isNewVersion: isNewVersion,
      stale: result.failure != null,
      validatedAt: result.validatedAt,
    );
    return true;
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

  Future<void> _showVersionDialog(
    BuildContext context,
    UpdateModel info,
    String currentVersion, {
    required bool isNewVersion,
    required bool stale,
    DateTime? validatedAt,
  }) async {
    var closing = false;
    final title = stale
        ? '上次获取的版本日志 ${info.tagName}'
        : isNewVersion
        ? '发现新版本 ${info.tagName}'
        : '当前已是最新版本 ${info.tagName}';
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        constraints: const BoxConstraints(maxWidth: 560),
        scrollable: true,
        title: Text(title),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('当前版本 $currentVersion'),
            if (stale) ...[
              const SizedBox(height: 8),
              const Text('本次刷新失败，以下为上次成功获取的版本日志。'),
              if (validatedAt != null)
                Text('上次获取时间 ${_formatTime(validatedAt)}'),
            ],
            if (defaultTargetPlatform == TargetPlatform.iOS)
              const Text('下载 iOS 安装包后，使用个人签名工具签名并侧载。'),
            const SizedBox(height: 8),
            Text(
              isNewVersion ? '更新内容' : '版本日志',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            if (info.body.trim().isEmpty)
              const Text('暂无更新说明')
            else
              ReleaseNotesMarkdown(
                data: info.body,
                onTapLink: (href) => _launchExternalUrl(context, href),
              ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              if (closing) return;
              closing = true;
              Navigator.pop(dialogContext);
            },
            child: Text(isNewVersion ? '稍后' : '知道了'),
          ),
          if (isNewVersion)
            FilledButton(
              onPressed: () {
                if (closing) return;
                closing = true;
                Navigator.pop(dialogContext);
                _launchExternalUrl(
                  context,
                  defaultTargetPlatform == TargetPlatform.iOS
                      ? info.htmlUrl
                      : info.downloadUrl,
                );
              },
              child: Text(
                defaultTargetPlatform == TargetPlatform.iOS ? '查看发行版' : '立即更新',
              ),
            ),
        ],
      ),
    );
  }

  String _formatTime(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int part) => part.toString().padLeft(2, '0');
    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}';
  }

  Future<void> _launchExternalUrl(BuildContext context, String url) async {
    if (!await GithubProxy.launchExternalUrlString(url)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('无法打开链接')));
      }
    }
  }
}
