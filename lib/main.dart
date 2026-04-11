import 'package:cqut/routes/Routes.dart';
import 'package:cqut/app/app_bootstrap.dart';
import 'package:flutter/material.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await bootstrapAndRunApp(getRootWidget);
}
