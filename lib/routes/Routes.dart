import 'package:cqut/manager/theme_manager.dart';
import 'package:cqut/pages/Login/Login.dart';
import 'package:cqut/pages/Main/Main.dart';
import 'package:cqut/theme/schedule_course_card_theme.dart';
import 'package:dynamic_color/dynamic_color.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

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
            final themeManager = ThemeManager();
            ColorScheme lightScheme;
            if (themeManager.isSystemColor && lightDynamic != null) {
              lightScheme = lightDynamic.harmonized();
            } else if (themeManager.isSystemColor) {
              lightScheme = ColorScheme.fromSeed(seedColor: defaultSeedColor);
            } else {
              lightScheme = ColorScheme.fromSeed(
                seedColor: themeManager.customColor,
              );
            }

            ColorScheme darkScheme;
            if (themeManager.isSystemColor && darkDynamic != null) {
              darkScheme = darkDynamic.harmonized();
            } else if (themeManager.isSystemColor) {
              darkScheme = ColorScheme.fromSeed(
                seedColor: defaultSeedColor,
                brightness: Brightness.dark,
              );
            } else {
              darkScheme = ColorScheme.fromSeed(
                seedColor: themeManager.customColor,
                brightness: Brightness.dark,
              );
            }

            return MaterialApp(
              title: 'CQUT Helper',
              initialRoute: "/",
              routes: getRootRoutes(),
              // 添加 Firebase Analytics 监听
              navigatorObservers: [
                FirebaseAnalyticsObserver(
                  analytics: FirebaseAnalytics.instance,
                ),
              ],
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: ThemeData(
                useMaterial3: true,
                colorScheme: lightScheme,
                extensions: <ThemeExtension<dynamic>>[
                  ScheduleCourseCardTheme.light(),
                ],
              ),
              darkTheme: ThemeData(
                useMaterial3: true,
                colorScheme: darkScheme,
                extensions: <ThemeExtension<dynamic>>[
                  ScheduleCourseCardTheme.dark(),
                ],
              ),
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
