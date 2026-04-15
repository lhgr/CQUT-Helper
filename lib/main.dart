import 'package:cqut_helper/routes/Routes.dart';
import 'package:cqut_helper/app/app_bootstrap.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await bootstrapAndRunApp(getRootWidget);
}
