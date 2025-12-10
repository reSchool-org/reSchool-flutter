import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _displayOnlyCurrentClass = false;
  int _hwDaysPast = 14;
  int _hwDaysFuture = 14;

  bool get displayOnlyCurrentClass => _displayOnlyCurrentClass;
  int get hwDaysPast => _hwDaysPast;
  int get hwDaysFuture => _hwDaysFuture;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _displayOnlyCurrentClass = prefs.getBool('display_only_current_class') ?? false;
    _hwDaysPast = prefs.getInt('hw_days_past') ?? 14;
    _hwDaysFuture = prefs.getInt('hw_days_future') ?? 14;
    notifyListeners();
  }

  Future<void> setDisplayOnlyCurrentClass(bool value) async {
    _displayOnlyCurrentClass = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('display_only_current_class', value);
  }

  Future<void> setHwDaysPast(int value) async {
    _hwDaysPast = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hw_days_past', value);
  }

  Future<void> setHwDaysFuture(int value) async {
    _hwDaysFuture = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('hw_days_future', value);
  }
}
