import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/routes/Routes.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'firebase_options.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 初始化 Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // 设置沉浸式状态栏
  await ThemeManager().init();
  runApp(getRootWidget());
}
