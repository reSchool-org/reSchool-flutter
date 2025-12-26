import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/widget_models.dart';

class WidgetConfigProvider extends ChangeNotifier {
  static const String _configKey = 'widget_config';

  WidgetConfig _config = WidgetConfig();
  bool _isLoading = true;

  WidgetConfig get config => _config;
  bool get isLoading => _isLoading;

  bool get scheduleEnabled => _config.scheduleEnabled;
  bool get homeworkEnabled => _config.homeworkEnabled;
  bool get gradesEnabled => _config.gradesEnabled;
  int get homeworkItemsCount => _config.homeworkItemsCount;
  int get gradesSubjectsCount => _config.gradesSubjectsCount;
  bool get showTeacherInSchedule => _config.showTeacherInSchedule;
  bool get showDeadlineInHomework => _config.showDeadlineInHomework;

  WidgetConfigProvider() {
    _loadConfig();
  }

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final configJson = prefs.getString(_configKey);

      if (configJson != null) {
        _config = WidgetConfig.fromJson(jsonDecode(configJson));
      }
    } catch (e) {
      debugPrint('Error loading widget config: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(_config.toJson()));
    } catch (e) {
      debugPrint('Error saving widget config: $e');
    }
  }

  Future<void> setScheduleEnabled(bool value) async {
    _config = _config.copyWith(scheduleEnabled: value);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setHomeworkEnabled(bool value) async {
    _config = _config.copyWith(homeworkEnabled: value);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setGradesEnabled(bool value) async {
    _config = _config.copyWith(gradesEnabled: value);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setHomeworkItemsCount(int count) async {
    _config = _config.copyWith(homeworkItemsCount: count.clamp(1, 20));
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setGradesSubjectsCount(int count) async {
    _config = _config.copyWith(gradesSubjectsCount: count.clamp(1, 15));
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setShowTeacherInSchedule(bool value) async {
    _config = _config.copyWith(showTeacherInSchedule: value);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> setShowDeadlineInHomework(bool value) async {
    _config = _config.copyWith(showDeadlineInHomework: value);
    notifyListeners();
    await _saveConfig();
  }

  Future<void> resetToDefaults() async {
    _config = WidgetConfig();
    notifyListeners();
    await _saveConfig();
  }
}