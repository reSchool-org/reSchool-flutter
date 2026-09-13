import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../providers/settings_provider.dart';

const defaultAppFontKey = 'rubik';

/// The active setting remains available even inside a captured route theme.
class AppFontScope extends InheritedWidget {
  final String fontKey;
  const AppFontScope({super.key, required this.fontKey, required super.child});

  @override
  bool updateShouldNotify(AppFontScope oldWidget) =>
      fontKey != oldWidget.fontKey;
}

/// храним шрифт в ThemeData, чтобы все оформленные элементы получали его изменения
class AppFontTheme extends ThemeExtension<AppFontTheme> {
  final String key;
  const AppFontTheme(this.key);

  @override
  AppFontTheme copyWith({String? key}) => AppFontTheme(key ?? this.key);

  @override
  AppFontTheme lerp(covariant AppFontTheme? other, double t) =>
      other == null || t < 0.5 ? this : other;
}

String appFontName(String key) => switch (key) {
  'rubik' => 'Rubik',
  'golosText' => 'Golos Text',
  'nunito' => 'Nunito',
  'manrope' => 'Manrope',
  'ptSans' => 'PT Sans',
  _ => 'Inter',
};

TextTheme appTextTheme(String key, TextTheme base) =>
    GoogleFonts.getTextTheme(appFontName(key), base);

TextStyle appFont(
  BuildContext context, {
  TextStyle? textStyle,
  double? fontSize,
  FontWeight? fontWeight,
  Color? color,
  double? letterSpacing,
  double? height,
  TextDecoration? decoration,
  FontStyle? fontStyle,
  double? wordSpacing,
  Paint? foreground,
  Paint? background,
  List<Shadow>? shadows,
  TextDecorationStyle? decorationStyle,
  Color? decorationColor,
  double? decorationThickness,
}) {
  final settings = Provider.of<SettingsProvider?>(context, listen: false);
  final scope = context.dependOnInheritedWidgetOfExactType<AppFontScope>();
  final key =
      scope?.fontKey ??
      settings?.fontFamily ??
      Theme.of(context).extension<AppFontTheme>()?.key;
  final style = (textStyle ?? const TextStyle()).merge(
    TextStyle(
      fontSize: fontSize,
      fontWeight: fontWeight,
      color: color,
      letterSpacing: letterSpacing,
      height: height,
      decoration: decoration,
      fontStyle: fontStyle,
      wordSpacing: wordSpacing,
      foreground: foreground,
      background: background,
      shadows: shadows,
      decorationStyle: decorationStyle,
      decorationColor: decorationColor,
      decorationThickness: decorationThickness,
    ),
  );
  // вне reschool виджет наследует тему текста приложения, в которое встроен
  return key == null
      ? style
      : GoogleFonts.getFont(appFontName(key), textStyle: style);
}
