import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/widget_models.dart';
import '../services/widget_data_service.dart';

/// настройки виджетов
class WidgetConfigProvider extends ChangeNotifier {
  static const String _configKey = 'widget_config';

  WidgetConfig _config = WidgetConfig();
  bool _isLoading = true;
  bool _disposed = false;
  late final Future<void> ready;
  Future<void> _pendingSave = Future.value();

  WidgetConfig get config => _config;
  bool get isLoading => _isLoading;

  // геттеры для удобства
  bool get scheduleEnabled => _config.scheduleEnabled;
  bool get homeworkEnabled => _config.homeworkEnabled;
  bool get gradesEnabled => _config.gradesEnabled;
  int get homeworkItemsCount => _config.homeworkItemsCount;
  int get gradesSubjectsCount => _config.gradesSubjectsCount;
  bool get showTeacherInSchedule => _config.showTeacherInSchedule;
  bool get showDeadlineInHomework => _config.showDeadlineInHomework;

  WidgetConfigProvider() {
    ready = _loadConfig();
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
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> _saveConfig() {
    final snapshot = _config;
    final result = _pendingSave.then((_) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_configKey, jsonEncode(snapshot.toJson()));
      await WidgetDataService().updateConfiguration(snapshot);
    });
    _pendingSave = result.catchError((Object error) {
      debugPrint('Error saving widget config: $error');
    });
    return _pendingSave;
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }

  /// переключить виджет расписания
  Future<void> setScheduleEnabled(bool value) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(scheduleEnabled: value);
    notifyListeners();
    await _saveConfig();
  }

  /// переключить виджет домашних заданий
  Future<void> setHomeworkEnabled(bool value) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(homeworkEnabled: value);
    notifyListeners();
    await _saveConfig();
  }

  /// переключить виджет оценок
  Future<void> setGradesEnabled(bool value) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(gradesEnabled: value);
    notifyListeners();
    await _saveConfig();
  }

  /// сколько домашек показывать
  Future<void> setHomeworkItemsCount(int count) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(homeworkItemsCount: count.clamp(1, 20));
    notifyListeners();
    await _saveConfig();
  }

  /// сколько предметов показывать в виджете оценок
  Future<void> setGradesSubjectsCount(int count) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(gradesSubjectsCount: count.clamp(1, 15));
    notifyListeners();
    await _saveConfig();
  }

  /// показывать ли учителя в расписании
  Future<void> setShowTeacherInSchedule(bool value) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(showTeacherInSchedule: value);
    notifyListeners();
    await _saveConfig();
  }

  /// показывать ли дедлайн у домашнего задания
  Future<void> setShowDeadlineInHomework(bool value) async {
    await ready;
    if (_disposed) return;
    _config = _config.copyWith(showDeadlineInHomework: value);
    notifyListeners();
    await _saveConfig();
  }

  /// вернуть настройки к дефолтным
  Future<void> resetToDefaults() async {
    await ready;
    if (_disposed) return;
    _config = WidgetConfig();
    notifyListeners();
    await _saveConfig();
  }
}
