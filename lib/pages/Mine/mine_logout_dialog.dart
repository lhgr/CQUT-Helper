import 'package:cqut/api/auth/auth_api.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> showMineLogoutDialog(BuildContext context) async {
  await showDialog<void>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("退出登录"),
      content: Text("确定要退出当前账号吗？"),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text("取消"),
        ),
        TextButton(
          onPressed: () async {
            final prefs = await SharedPreferences.getInstance();
            await prefs.remove('account');
            await prefs.remove('encrypted_password');
            await AuthApi().resetLoginContext();
            if (context.mounted) {
              Navigator.pop(context);
              ScaffoldMessenger.of(
                context,
              ).showSnackBar(SnackBar(content: Text("已退出登录")));
              Navigator.of(context).pushReplacementNamed('/login');
            }
          },
          child: Text("确定"),
        ),
      ],
    ),
  );
}
