import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/pages/Login/Login.dart';
import 'package:cqut/pages/Main/Main.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    const defaultSeedColor = Colors.blue;

    return ListenableBuilder(
      listenable: ThemeManager(),
      builder: (context, child) {
        return DynamicColorBuilder(
          builder: (ColorScheme? lightDynamic, ColorScheme? darkDynamic) {
            ColorScheme lightScheme;
            if (lightDynamic != null) {
              lightScheme = lightDynamic.harmonized();
            } else {
              lightScheme = ColorScheme.fromSeed(seedColor: defaultSeedColor);
            }

            ColorScheme darkScheme;
            if (darkDynamic != null) {
              darkScheme = darkDynamic.harmonized();
            } else {
              darkScheme = ColorScheme.fromSeed(
                seedColor: defaultSeedColor,
                brightness: Brightness.dark,
              );
            }

            return MaterialApp(
              title: 'CQUTer Helper',
              initialRoute: "/",
              routes: getRootRoutes(),
              // 添加 Firebase Analytics 监听
              navigatorObservers: [
                FirebaseAnalyticsObserver(
                  analytics: FirebaseAnalytics.instance,
                ),
              ],
              theme: ThemeData(useMaterial3: true, colorScheme: lightScheme),
              darkTheme: ThemeData(useMaterial3: true, colorScheme: darkScheme),
              themeMode: ThemeManager().themeMode,
            );
          },
        );
      },
    );
  }
}

Widget getRootWidget() {
  return const MyApp();
}

Map<String, Widget Function(BuildContext)> getRootRoutes() {
  return {"/": (context) => MainPage(), "/login": (context) => LoginPage()};
}
