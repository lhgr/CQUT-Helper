import 'package:cqut_helper/pages/Settings/app_settings_page.dart';
import 'package:cqut_helper/pages/MessageCenter/message_center_page.dart';
import 'package:flutter/material.dart';

import 'mine_logout_dialog.dart';
import 'mine_menu_item.dart';

class MineMenuSection extends StatelessWidget {
  const MineMenuSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        MineMenuItem(
          icon: Icons.notifications_none_rounded,
          title: '消息中心',
          subtitle: '调课记录、课表变更与应用公告',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const MessageCenterPage()),
          ),
        ),
        const SizedBox(height: 12),
        MineMenuItem(
          icon: Icons.settings,
          title: "设置",
          subtitle: "课表、提醒、外观、存储与关于",
          onTap: () => openAppSettings(context),
        ),
        const SizedBox(height: 24),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () {
              showMineLogoutDialog(context);
            },
            icon: const Icon(Icons.logout),
            label: const Text("退出登录"),
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
