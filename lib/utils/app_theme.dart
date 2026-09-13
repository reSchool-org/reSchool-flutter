import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'app_font.dart';

ThemeData buildAppTheme({
  required String fontKey,
  required Color accentColor,
  required Brightness brightness,
}) {
  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: ColorScheme.fromSeed(
      seedColor: accentColor,
      brightness: brightness,
    ),
  );
  TextStyle font(TextStyle style) =>
      GoogleFonts.getFont(appFontName(fontKey), textStyle: style);
  final cupertino = MaterialBasedCupertinoThemeData(materialTheme: base);
  final text = cupertino.textTheme;

  return base.copyWith(
    extensions: [AppFontTheme(fontKey)],
    textTheme: appTextTheme(fontKey, base.textTheme),
    primaryTextTheme: appTextTheme(fontKey, base.primaryTextTheme),
    cupertinoOverrideTheme: CupertinoThemeData(
      textTheme: text.copyWith(
        textStyle: font(text.textStyle),
        actionTextStyle: font(text.actionTextStyle),
        actionSmallTextStyle: font(text.actionSmallTextStyle),
        tabLabelTextStyle: font(text.tabLabelTextStyle),
        navTitleTextStyle: font(text.navTitleTextStyle),
        navLargeTitleTextStyle: font(text.navLargeTitleTextStyle),
        navActionTextStyle: font(text.navActionTextStyle),
        pickerTextStyle: font(text.pickerTextStyle),
        dateTimePickerTextStyle: font(text.dateTimePickerTextStyle),
      ),
    ),
  );
}
