import 'package:cqut_helper/manager/app_backup_service.dart';
import 'package:cqut_helper/utils/document_file_service.dart';
import 'package:flutter/material.dart';

class BackupRestorePage extends StatefulWidget {
  const BackupRestorePage({super.key});

  @override
  State<BackupRestorePage> createState() => _BackupRestorePageState();
}

class _BackupRestorePageState extends State<BackupRestorePage> {
  bool _busy = false;

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _export() async {
    setState(() => _busy = true);
    try {
      final content = await AppBackupService.createBackup();
      final now = DateTime.now();
      String two(int value) => value.toString().padLeft(2, '0');
      final name =
          'CQUT-Helper-${now.year}${two(now.month)}${two(now.day)}-${two(now.hour)}${two(now.minute)}.json';
      final uri = await DocumentFileService.saveText(
        fileName: name,
        mimeType: 'application/json',
        content: content,
      );
      if (uri != null) _message('备份已保存');
    } catch (error) {
      _message('备份失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    try {
      final content = await DocumentFileService.openText();
      if (content == null) return;
      final preview = AppBackupService.preview(content);
      if (!mounted) return;
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('恢复这份备份？'),
          content: Text(
            '备份账号：${preview.sourceAccount}\n'
            '创建时间：${preview.createdAt}\n'
            '应用设置：${preview.preferenceCount} 项\n'
            '课程个性化：${preview.coursePreferenceCount} 项\n\n'
            '同名设置和课程偏好会被备份内容覆盖；密码、登录账号、课表缓存和日志不会导入。',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('确认恢复'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      final result = await AppBackupService.restore(content);
      _message(
        '已恢复 ${result.preferenceCount} 项设置、${result.coursePreferenceCount} 项课程偏好',
      );
    } catch (error) {
      _message('恢复失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备份与恢复')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Card(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                '备份包含源学号、课表布局、提醒设置、主题、课程别名、备注、颜色和隐藏状态。'
                '源学号只用于提示备份归属；不会包含登录密码、可用于登录的凭据、日志、课表缓存和背景图片。',
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _export,
            icon: const Icon(Icons.file_upload_outlined),
            label: const Text('导出备份文件'),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: _busy ? null : _restore,
            icon: const Icon(Icons.file_download_outlined),
            label: const Text('选择备份文件恢复'),
          ),
          if (_busy) ...[
            const SizedBox(height: 24),
            const Center(child: CircularProgressIndicator()),
          ],
        ],
      ),
    );
  }
}
