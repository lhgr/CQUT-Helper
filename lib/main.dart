import 'package:cqut_helper/routes/Routes.dart';
import 'package:cqut_helper/app/app_bootstrap.dart';
import 'package:cqut_helper/utils/app_logger.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppLogger.I.installGlobalErrorHandlers();
  await bootstrapAndRunApp(getRootWidget);
}
