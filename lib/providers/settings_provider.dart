import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SettingsProvider extends ChangeNotifier {
  bool _displayOnlyCurrentClass = false;
  bool _cloudFeaturesEnabled = false;
  String? _cloudToken;
  int? _serverThreadId;
  int _hwDaysPast = 14;
  int _hwDaysFuture = 14;
  Locale _locale = const Locale('ru');

  bool get displayOnlyCurrentClass => _displayOnlyCurrentClass;
  bool get cloudFeaturesEnabled => _cloudFeaturesEnabled;
  String? get cloudToken => _cloudToken;
  int? get serverThreadId => _serverThreadId;
  int get hwDaysPast => _hwDaysPast;
  int get hwDaysFuture => _hwDaysFuture;
  Locale get locale => _locale;

  SettingsProvider() {
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _displayOnlyCurrentClass = prefs.getBool('display_only_current_class') ?? false;
    _cloudFeaturesEnabled = prefs.getBool('cloud_features_enabled') ?? false;
    _cloudToken = prefs.getString('cloud_token');
    _serverThreadId = prefs.getInt('server_thread_id');
    _hwDaysPast = prefs.getInt('hw_days_past') ?? 14;
    _hwDaysFuture = prefs.getInt('hw_days_future') ?? 14;

    final String? languageCode = prefs.getString('language_code');
    if (languageCode != null) {
      _locale = Locale(languageCode);
    }

    notifyListeners();
  }

  Future<void> setDisplayOnlyCurrentClass(bool value) async {
    _displayOnlyCurrentClass = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('display_only_current_class', value);
  }

  Future<void> setCloudFeaturesEnabled(bool value) async {
    _cloudFeaturesEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('cloud_features_enabled', value);
  }

  Future<void> setCloudToken(String? value) async {
    _cloudToken = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('cloud_token');
    } else {
      await prefs.setString('cloud_token', value);
    }
  }

  Future<void> setServerThreadId(int? value) async {
    _serverThreadId = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove('server_thread_id');
    } else {
      await prefs.setInt('server_thread_id', value);
    }
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

  Future<void> setLocale(Locale locale) async {
    if (_locale == locale) return;
    _locale = locale;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('language_code', locale.languageCode);
  }
}