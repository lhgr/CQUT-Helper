import 'dart:math' as math;

import 'package:flutter/material.dart';

@immutable
class ScheduleCourseCardTheme extends ThemeExtension<ScheduleCourseCardTheme> {
  static const double _darkBackgroundLightness = 0.2;
  static const double _darkBorderLightness = 0.38;
  static const double _darkTitleLightness = 0.8;
  static const double _darkDescriptionLightness = 0.72;
  static const double _darkButtonLightness = 0.68;

  static const List<Color> _lightBackgrounds = [
    Color(0xFFE6F4FF),
    Color(0xFFFDEBDD),
    Color(0xFFDEFBF7),
    Color(0xFFEEEDFF),
    Color(0xFFFCEBCD),
    Color(0xFFFFEFF0),
    Color(0xFFFFEEF8),
    Color(0xFFE2F9F3),
    Color(0xFFFFF9C9),
    Color(0xFFFAEDFF),
    Color(0xFFF4F2FD),
    Color(0xFFE6E6FF),
    Color(0xFFEEFDDD),
    Color(0xFFEADEFB),
    Color(0xFFFFEFED),
    Color(0xFFCDF2FC),
    Color(0xFFEFFFFF),
    Color(0xFFEEFFFF),
    Color(0xFFF9F5E2),
    Color(0xFFEDF0FF),
    Color(0xFFF2F4FD),
  ];

  static const List<Color> _lightTitleColors = [
    Color(0xFF1473A3),
    Color(0xFFAC3E15),
    Color(0xFF0F7B78),
    Color(0xFF621EA4),
    Color(0xFF915D12),
    Color(0xFFAC1522),
    Color(0xFFAC152C),
    Color(0xFF0F7A7B),
    Color(0xFF846C10),
    Color(0xFF781CA6),
    Color(0xFF3215AC),
    Color(0xFF1426A3),
    Color(0xFF80AC15),
    Color(0xFF480F7B),
    Color(0xFFA4671E),
    Color(0xFF127B91),
    Color(0xFF15ACA8),
    Color(0xFF1568AC),
    Color(0xFF717B0F),
    Color(0xFF1C3CA6),
    Color(0xFF152EAC),
  ];

  final List<Color> backgrounds;
  final List<Color> borders;
  final List<Color> titleColors;
  final List<Color> descriptionColors;
  final List<Color> buttonColors;

  const ScheduleCourseCardTheme({
    required this.backgrounds,
    required this.borders,
    required this.titleColors,
    required this.descriptionColors,
    required this.buttonColors,
  });

  factory ScheduleCourseCardTheme.light() {
    final borders = List<Color>.generate(
      _lightBackgrounds.length,
      (index) =>
          Color.lerp(
            _lightBackgrounds[index],
            _lightTitleColors[index],
            0.22,
          ) ??
          _lightBackgrounds[index],
      growable: false,
    );
    return ScheduleCourseCardTheme(
      backgrounds: List<Color>.from(_lightBackgrounds, growable: false),
      borders: borders,
      titleColors: List<Color>.from(_lightTitleColors, growable: false),
      descriptionColors: List<Color>.from(_lightTitleColors, growable: false),
      buttonColors: List<Color>.from(_lightTitleColors, growable: false),
    );
  }

  factory ScheduleCourseCardTheme.dark() {
    final light = ScheduleCourseCardTheme.light();
    return ScheduleCourseCardTheme(
      backgrounds: light.backgrounds
          .map(
            (color) => _colorForDarkSurface(
              color,
              lightness: _darkBackgroundLightness,
              saturation: 0.42,
            ),
          )
          .toList(growable: false),
      borders: light.borders
          .map(
            (color) => _colorForDarkSurface(
              color,
              lightness: _darkBorderLightness,
              saturation: 0.5,
            ),
          )
          .toList(growable: false),
      titleColors: light.titleColors
          .map(
            (color) => _colorForDarkSurface(
              color,
              lightness: _darkTitleLightness,
              saturation: 0.58,
            ),
          )
          .toList(growable: false),
      descriptionColors: light.descriptionColors
          .map(
            (color) => _colorForDarkSurface(
              color,
              lightness: _darkDescriptionLightness,
              saturation: 0.42,
            ),
          )
          .toList(growable: false),
      buttonColors: light.buttonColors
          .map(
            (color) => _colorForDarkSurface(
              color,
              lightness: _darkButtonLightness,
              saturation: 0.58,
            ),
          )
          .toList(growable: false),
    );
  }

  int _safeIndex(int index) {
    if (backgrounds.isEmpty) {
      return 0;
    }
    return index % backgrounds.length;
  }

  Color backgroundAt(int index) => backgrounds[_safeIndex(index)];
  Color borderAt(int index) => borders[_safeIndex(index)];
  Color titleAt(int index) => titleColors[_safeIndex(index)];
  Color descriptionAt(int index) => descriptionColors[_safeIndex(index)];
  Color buttonAt(int index) => buttonColors[_safeIndex(index)];

  Color onButtonAt(int index) {
    final buttonColor = buttonAt(index);
    const white = Colors.white;
    const black = Colors.black;
    final whiteContrast = _contrastRatio(buttonColor, white);
    final blackContrast = _contrastRatio(buttonColor, black);
    return whiteContrast >= blackContrast ? white : black;
  }

  @override
  ScheduleCourseCardTheme copyWith({
    List<Color>? backgrounds,
    List<Color>? borders,
    List<Color>? titleColors,
    List<Color>? descriptionColors,
    List<Color>? buttonColors,
  }) {
    return ScheduleCourseCardTheme(
      backgrounds: backgrounds ?? this.backgrounds,
      borders: borders ?? this.borders,
      titleColors: titleColors ?? this.titleColors,
      descriptionColors: descriptionColors ?? this.descriptionColors,
      buttonColors: buttonColors ?? this.buttonColors,
    );
  }

  @override
  ThemeExtension<ScheduleCourseCardTheme> lerp(
    covariant ThemeExtension<ScheduleCourseCardTheme>? other,
    double t,
  ) {
    if (other is! ScheduleCourseCardTheme) {
      return this;
    }
    final maxLength = backgrounds.length;
    return ScheduleCourseCardTheme(
      backgrounds: List<Color>.generate(
        maxLength,
        (index) =>
            Color.lerp(backgrounds[index], other.backgrounds[index], t) ??
            backgrounds[index],
        growable: false,
      ),
      borders: List<Color>.generate(
        maxLength,
        (index) =>
            Color.lerp(borders[index], other.borders[index], t) ??
            borders[index],
        growable: false,
      ),
      titleColors: List<Color>.generate(
        maxLength,
        (index) =>
            Color.lerp(titleColors[index], other.titleColors[index], t) ??
            titleColors[index],
        growable: false,
      ),
      descriptionColors: List<Color>.generate(
        maxLength,
        (index) =>
            Color.lerp(
              descriptionColors[index],
              other.descriptionColors[index],
              t,
            ) ??
            descriptionColors[index],
        growable: false,
      ),
      buttonColors: List<Color>.generate(
        maxLength,
        (index) =>
            Color.lerp(buttonColors[index], other.buttonColors[index], t) ??
            buttonColors[index],
        growable: false,
      ),
    );
  }

  static Color _colorForDarkSurface(
    Color color, {
    required double lightness,
    required double saturation,
  }) {
    final hsl = HSLColor.fromColor(color);
    final adjusted = hsl
        .withSaturation(saturation.clamp(0.0, 1.0))
        .withLightness(lightness.clamp(0.0, 1.0));
    return adjusted.toColor();
  }

  static double _channelToLinear(double value) {
    if (value <= 0.03928) {
      return value / 12.92;
    }
    return math.pow((value + 0.055) / 1.055, 2.4).toDouble();
  }

  static double _relativeLuminance(Color color) {
    final r = _channelToLinear(color.r);
    final g = _channelToLinear(color.g);
    final b = _channelToLinear(color.b);
    return 0.2126 * r + 0.7152 * g + 0.0722 * b;
  }

  static double _contrastRatio(Color a, Color b) {
    final la = _relativeLuminance(a);
    final lb = _relativeLuminance(b);
    final lighter = la > lb ? la : lb;
    final darker = la > lb ? lb : la;
    return (lighter + 0.05) / (darker + 0.05);
  }
}
