import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../utils/time_utils.dart';

class LessonTime {
  final String start;
  final String end;

  const LessonTime({required this.start, required this.end});

  Map<String, dynamic> toJson() => {'start': start, 'end': end};

  factory LessonTime.fromJson(Map<String, dynamic> json) {
    return LessonTime(
      start: json['start'] as String,
      end: json['end'] as String,
    );
  }

  LessonTime copyWith({String? start, String? end}) {
    return LessonTime(
      start: start ?? this.start,
      end: end ?? this.end,
    );
  }
}

class BellSchedulePreset {
  final String id;
  final String name;
  final String? subtitle;
  final Map<int, LessonTime> lessons;
  final int defaultOffset;

  const BellSchedulePreset({
    required this.id,
    required this.name,
    this.subtitle,
    required this.lessons,
    this.defaultOffset = 0,
  });
}

class BellScheduleProvider extends ChangeNotifier {
  static const String _storageKey = 'bell_schedule';
  static const String _presetKey = 'bell_schedule_preset';
  static const String _offsetKey = 'bell_schedule_offset';

  String _currentPresetId = 'custom';
  Map<int, LessonTime> _schedule = {};
  int _timeOffset = 0;

  String get currentPresetId => _currentPresetId;
  Map<int, LessonTime> get schedule => Map.unmodifiable(_schedule);
  int get timeOffset => _timeOffset;

  static final List<BellSchedulePreset> presets = [
    const BellSchedulePreset(
      id: 'fml30_shevchenko',
      name: 'ФМЛ № 30',
      subtitle: 'ул. Шевченко, 23, корп.2',
      defaultOffset: 126,
      lessons: {
        1: LessonTime(start: '08:50', end: '09:35'),
        2: LessonTime(start: '09:45', end: '10:30'),
        3: LessonTime(start: '10:45', end: '11:30'),
        4: LessonTime(start: '11:50', end: '12:35'),
        5: LessonTime(start: '12:55', end: '13:40'),
        6: LessonTime(start: '13:55', end: '14:40'),
        7: LessonTime(start: '14:50', end: '15:35'),
      },
    ),
    const BellSchedulePreset(
      id: 'fml30_7liniya',
      name: 'ФМЛ № 30',
      subtitle: '7 Линия, 52',
      lessons: {
        1: LessonTime(start: '08:30', end: '09:15'),
        2: LessonTime(start: '09:25', end: '10:10'),
        3: LessonTime(start: '10:25', end: '11:10'),
        4: LessonTime(start: '11:30', end: '12:15'),
        5: LessonTime(start: '12:35', end: '13:20'),
        6: LessonTime(start: '13:35', end: '14:20'),
        7: LessonTime(start: '14:30', end: '15:15'),
        8: LessonTime(start: '15:25', end: '16:10'),
      },
    ),
    const BellSchedulePreset(
      id: 'fml239',
      name: 'ФМЛ № 239',
      subtitle: null,
      lessons: {
        0: LessonTime(start: '08:20', end: '09:05'),
        1: LessonTime(start: '09:15', end: '10:00'),
        2: LessonTime(start: '10:10', end: '10:55'),
        3: LessonTime(start: '11:10', end: '11:55'),
        4: LessonTime(start: '12:10', end: '12:55'),
        5: LessonTime(start: '13:25', end: '14:10'),
        6: LessonTime(start: '14:20', end: '15:05'),
        7: LessonTime(start: '15:15', end: '16:00'),
      },
    ),
  ];

  static const Map<int, LessonTime> defaultSchedule = {
    1: LessonTime(start: '09:00', end: '09:45'),
    2: LessonTime(start: '10:00', end: '10:45'),
    3: LessonTime(start: '11:00', end: '11:45'),
    4: LessonTime(start: '12:00', end: '12:45'),
    5: LessonTime(start: '13:00', end: '13:45'),
    6: LessonTime(start: '14:00', end: '14:45'),
    7: LessonTime(start: '15:00', end: '15:45'),
  };

  BellScheduleProvider() {
    _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    _currentPresetId = prefs.getString(_presetKey) ?? 'custom';
    _timeOffset = prefs.getInt(_offsetKey) ?? 0;

    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        _schedule = data.map((key, value) => MapEntry(
          int.parse(key),
          LessonTime.fromJson(value as Map<String, dynamic>),
        ));
      } catch (e) {
        _schedule = Map.from(defaultSchedule);
      }
    } else {
      _schedule = Map.from(defaultSchedule);
    }
    notifyListeners();
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, _currentPresetId);
    await prefs.setInt(_offsetKey, _timeOffset);

    final data = _schedule.map((key, value) => MapEntry(
      key.toString(),
      value.toJson(),
    ));
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  LessonTime? getLessonTime(int lessonNum, {bool applyOffset = true}) {
    final baseTime = _schedule[lessonNum];
    if (baseTime == null) return null;

    if (!applyOffset || _timeOffset == 0) return baseTime;

    return LessonTime(
      start: TimeUtils.addSeconds(baseTime.start, _timeOffset),
      end: TimeUtils.addSeconds(baseTime.end, _timeOffset),
    );
  }

  Future<void> setTimeOffset(int seconds) async {
    _timeOffset = seconds;
    notifyListeners();
    await _saveSchedule();
  }

  Future<void> applyPreset(String presetId) async {
    final preset = presets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => BellSchedulePreset(
        id: 'custom',
        name: 'Своё',
        lessons: defaultSchedule,
      ),
    );

    _currentPresetId = presetId;
    _schedule = Map.from(preset.lessons);
    _timeOffset = preset.defaultOffset;

    notifyListeners();
    await _saveSchedule();
  }

  Future<void> setLessonTime(int lessonNum, LessonTime time) async {
    _schedule[lessonNum] = time;
    _currentPresetId = 'custom';
    notifyListeners();
    await _saveSchedule();
  }

  Future<void> addLesson(int lessonNum, LessonTime time) async {
    _schedule[lessonNum] = time;
    _currentPresetId = 'custom';
    notifyListeners();
    await _saveSchedule();
  }

  Future<void> removeLesson(int lessonNum) async {
    _schedule.remove(lessonNum);
    _currentPresetId = 'custom';
    notifyListeners();
    await _saveSchedule();
  }

  Future<void> resetToDefault() async {
    _schedule = Map.from(defaultSchedule);
    _currentPresetId = 'custom';
    _timeOffset = 0;
    notifyListeners();
    await _saveSchedule();
  }

  List<int> get sortedLessonNumbers {
    final numbers = _schedule.keys.toList();
    numbers.sort();
    return numbers;
  }

  String get currentPresetName {
    if (_currentPresetId == 'custom') return 'Своё расписание';
    final preset = presets.firstWhere(
      (p) => p.id == _currentPresetId,
      orElse: () => const BellSchedulePreset(id: '', name: 'Своё расписание', lessons: {}),
    );
    return preset.subtitle != null ? '${preset.name} (${preset.subtitle})' : preset.name;
  }
}