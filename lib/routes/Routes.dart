import 'package:cqut_helper/manager/theme_manager.dart';
import 'package:cqut_helper/pages/Login/Login.dart';
import 'package:cqut_helper/pages/Main/Main.dart';
import 'package:cqut_helper/theme/app_theme.dart';
import 'package:cqut_helper/theme/dynamic_color_scheme.dart';
import 'package:dynamic_color/dynamic_color.dart';
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
          builder: (lightDynamic, darkDynamic) {
            final themeManager = ThemeManager();
            final predictiveBackEnabled = !themeManager.predictiveBackDisabled;
            final usesSystemColor =
                themeManager.colorSource == ThemeColorSource.system;
            final usesLightDynamicColor =
                usesSystemColor && lightDynamic != null;
            final usesDarkDynamicColor = usesSystemColor && darkDynamic != null;
            ColorScheme lightScheme;
            if (usesSystemColor && lightDynamic != null) {
              lightScheme = lightDynamic.harmonized().toFlutterColorScheme();
            } else if (usesSystemColor) {
              lightScheme = ColorScheme.fromSeed(seedColor: defaultSeedColor);
            } else {
              lightScheme = ColorScheme.fromSeed(
                seedColor: themeManager.activeSeedColor,
              );
            }

            ColorScheme darkScheme;
            if (usesSystemColor && darkDynamic != null) {
              darkScheme = darkDynamic.harmonized().toFlutterColorScheme();
            } else if (usesSystemColor) {
              darkScheme = ColorScheme.fromSeed(
                seedColor: defaultSeedColor,
                brightness: Brightness.dark,
              );
            } else {
              darkScheme = ColorScheme.fromSeed(
                seedColor: themeManager.activeSeedColor,
                brightness: Brightness.dark,
              );
            }

            return MaterialApp(
              title: 'CQUT Helper',
              initialRoute: "/",
              routes: getRootRoutes(),
              locale: const Locale('zh', 'CN'),
              supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
              localizationsDelegates: const [
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              theme: AppTheme.light(
                lightScheme,
                strengthenSurfaceContrast: usesLightDynamicColor,
                predictiveBackEnabled: predictiveBackEnabled,
              ),
              darkTheme: AppTheme.dark(
                darkScheme,
                strengthenSurfaceContrast: usesDarkDynamicColor,
                predictiveBackEnabled: predictiveBackEnabled,
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
