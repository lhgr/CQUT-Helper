import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/routes/Routes.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ThemeManager().init();
  runApp(getRootWidget());
}
