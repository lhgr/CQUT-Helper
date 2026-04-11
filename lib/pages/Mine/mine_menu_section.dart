import 'package:cqut/manager/update_manager.dart';
import 'package:cqut/pages/Mine/ClearCache.dart';
import 'package:flutter/material.dart';

import 'mine_about_dialog.dart';
import 'mine_logout_dialog.dart';
import 'mine_menu_item.dart';
import 'mine_theme_settings_sheet.dart';

class MineMenuSection extends StatelessWidget {
  const MineMenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MineMenuItem(
          icon: Icons.settings,
          title: "主题设置",
          onTap: () {
            showThemeSettingsSheet(context);
          },
        ),
        MineMenuItem(
          icon: Icons.system_update,
          title: "检查更新",
          onTap: () {
            UpdateManager().checkUpdate(context, showNoUpdateToast: true);
          },
        ),
        MineMenuItem(
          icon: Icons.cleaning_services,
          title: "清理缓存",
          onTap: () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ClearCachePage()),
            );
          },
        ),
        MineMenuItem(
          icon: Icons.info_outline,
          title: "关于我们",
          onTap: () {
            showMineAboutDialog(context);
          },
        ),
        SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () {
              showMineLogoutDialog(context);
            },
            icon: Icon(Icons.logout),
            label: Text("退出登录"),
            style: FilledButton.styleFrom(
              padding: EdgeInsets.symmetric(vertical: 16),
              backgroundColor: Theme.of(context).colorScheme.errorContainer,
              foregroundColor: Theme.of(context).colorScheme.onErrorContainer,
            ),
          ),
        ),
      ],
    );
  }
}
