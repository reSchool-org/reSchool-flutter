import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/widget_data_service.dart';

class AppColorTheme {
  final String id;
  final String name;
  final Color seed;

  const AppColorTheme({
    required this.id,
    required this.name,
    required this.seed,
  });
}

class ThemeProvider extends ChangeNotifier {
  static const String _defaultColorThemeId = 'blue';

  ThemeMode _themeMode = ThemeMode.system;
  String _colorThemeId = _defaultColorThemeId;

  ThemeMode get themeMode => _themeMode;
  String get colorThemeId => _colorThemeId;

  Color get accentColor => _findTheme(_colorThemeId).seed;
  AppColorTheme get currentColorTheme => _findTheme(_colorThemeId);

  static const List<AppColorTheme> colorThemes = [
    AppColorTheme(id: 'violet', name: 'Фиолет', seed: Color(0xFF6A11CB)),
    AppColorTheme(id: 'indigo', name: 'Индиго', seed: Color(0xFF4F46E5)),
    AppColorTheme(id: 'blue', name: 'Синий', seed: Color(0xFF1D6FEB)),
    AppColorTheme(id: 'teal', name: 'Бирюза', seed: Color(0xFF0D9488)),
    AppColorTheme(id: 'green', name: 'Зелёный', seed: Color(0xFF16A34A)),
    AppColorTheme(id: 'amber', name: 'Янтарь', seed: Color(0xFFD97706)),
    AppColorTheme(id: 'coral', name: 'Коралл', seed: Color(0xFFE53935)),
    AppColorTheme(id: 'pink', name: 'Розовый', seed: Color(0xFFDB2777)),
  ];

  AppColorTheme _findTheme(String id) {
    return colorThemes.firstWhere(
      (t) => t.id == id,
      orElse: () => colorThemes.firstWhere((t) => t.id == _defaultColorThemeId),
    );
  }

  ThemeProvider() {
    _loadTheme();
  }

  void setTheme(ThemeMode mode) {
    _themeMode = mode;
    notifyListeners();
    WidgetDataService().updateAppearance(accent: accentColor, mode: _themeMode);
    _saveTheme();
  }

  Future<void> setColorTheme(String id) async {
    _colorThemeId = id;
    notifyListeners();
    WidgetDataService().updateAppearance(accent: accentColor, mode: _themeMode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('color_theme_id', id);
  }

  Future<void> _loadTheme() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('theme_mode');
    if (saved == 'dark') {
      _themeMode = ThemeMode.dark;
    } else if (saved == 'light') {
      _themeMode = ThemeMode.light;
    } else {
      _themeMode = ThemeMode.system;
    }
    _colorThemeId = prefs.getString('color_theme_id') ?? _defaultColorThemeId;
    notifyListeners();
    WidgetDataService().updateAppearance(accent: accentColor, mode: _themeMode);
  }

  Future<void> _saveTheme() async {
    final prefs = await SharedPreferences.getInstance();
    if (_themeMode == ThemeMode.dark) {
      await prefs.setString('theme_mode', 'dark');
    } else if (_themeMode == ThemeMode.light) {
      await prefs.setString('theme_mode', 'light');
    } else {
      await prefs.remove('theme_mode');
    }
  }
}
