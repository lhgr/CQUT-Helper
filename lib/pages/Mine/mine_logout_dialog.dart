import 'package:cqut_helper/manager/account_session_manager.dart';
import 'package:flutter/material.dart';

Future<void> showMineLogoutDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("退出登录"),
      content: Text("确定要退出当前账号吗？"),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: Text("取消")),
        TextButton(
          onPressed: () async {
            final navigator = Navigator.of(context);
            final messenger = ScaffoldMessenger.of(context);
            try {
              await AccountSessionManager().logout();
              if (!context.mounted) return;
              navigator.pop();
              messenger.showSnackBar(const SnackBar(content: Text("已安全退出登录")));
              navigator.pushReplacementNamed('/login');
            } catch (_) {
              if (!context.mounted) return;
              messenger.showSnackBar(
                const SnackBar(content: Text("退出清理未完成，请重试")),
              );
            }
          },
          child: Text("确定"),
        ),
      ],
    ),
  );
}
