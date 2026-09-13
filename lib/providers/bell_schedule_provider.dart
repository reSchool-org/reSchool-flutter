import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'dart:convert';
import 'dart:async';

import '../services/bell_time_service.dart';
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
    return LessonTime(start: start ?? this.start, end: end ?? this.end);
  }
}

class BellSchedulePreset {
  final String id;
  final String name;
  final String? subtitle;
  final Map<int, LessonTime> lessons;
  final int defaultOffset;
  final bool isUserCreated;

  const BellSchedulePreset({
    required this.id,
    required this.name,
    this.subtitle,
    required this.lessons,
    this.defaultOffset = 0,
    this.isUserCreated = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'subtitle': subtitle,
    'defaultOffset': defaultOffset,
    'isUserCreated': isUserCreated,
    'lessons': lessons.map((k, v) => MapEntry(k.toString(), v.toJson())),
  };

  factory BellSchedulePreset.fromJson(Map<String, dynamic> json) {
    return BellSchedulePreset(
      id: json['id'] as String,
      name: json['name'] as String,
      subtitle: json['subtitle'] as String?,
      defaultOffset: json['defaultOffset'] as int? ?? 0,
      isUserCreated: json['isUserCreated'] as bool? ?? true,
      lessons: (json['lessons'] as Map<String, dynamic>).map(
        (k, v) => MapEntry(
          int.parse(k),
          LessonTime.fromJson(v as Map<String, dynamic>),
        ),
      ),
    );
  }

  BellSchedulePreset copyWith({
    String? name,
    String? subtitle,
    Map<int, LessonTime>? lessons,
    int? defaultOffset,
    bool clearSubtitle = false,
  }) {
    return BellSchedulePreset(
      id: id,
      name: name ?? this.name,
      subtitle: clearSubtitle ? null : (subtitle ?? this.subtitle),
      lessons: lessons ?? Map.from(this.lessons),
      defaultOffset: defaultOffset ?? this.defaultOffset,
      isUserCreated: isUserCreated,
    );
  }
}

class BellScheduleProvider extends ChangeNotifier with WidgetsBindingObserver {
  static const String _storageKey = 'bell_schedule';
  static const String _presetKey = 'bell_schedule_preset';
  static const String _offsetKey = 'bell_schedule_offset';
  static const String _autoScheduleKey = 'bell_auto_schedule';
  static const String _weekdayPresetsKey = 'bell_weekday_presets';
  static const String _userPresetsKey = 'bell_user_presets';
  static const String _correctionKey = 'bell_campus_corrections_v1';

  final BellTimeService _bellTime;
  final bool startTimers;
  late final Future<void> ready;
  Timer? _syncTimer;
  bool _disposed = false;
  final Map<String, bool> _serverModes = {};
  final Map<String, int> _manualOffsets = {};

  bool get supportsServerSync =>
      BellTimeService.campusIds.contains(effectivePresetId);
  bool usesServerFor(String id) =>
      BellTimeService.campusIds.contains(id) && (_serverModes[id] ?? true);
  bool get usesServerTime => usesServerFor(effectivePresetId);
  DateTime get now => usesServerTime ? _bellTime.moscowNow : DateTime.now();
  DateTime? get lastSyncedAt => _bellTime.lastSyncedAt;
  String get syncStatus {
    if (lastSyncedAt == null) {
      return _bellTime.error == null
          ? 'Получаем тайминги с reschool.app…'
          : 'Сервер недоступен. Пока используется базовое расписание без коррекции.';
    }
    final date = lastSyncedAt!.toLocal();
    final stamp =
        '${date.day.toString().padLeft(2, '0')}.${date.month.toString().padLeft(2, '0')}.${date.year} '
        '${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    return _bellTime.isStale
        ? 'Последняя синхронизация: $stamp. Используются сохранённые тайминги.'
        : 'Синхронизировано: $stamp. Обновление раз в сутки.';
  }

  String _currentPresetId = 'custom';
  Map<int, LessonTime> _schedule = {};
  int _timeOffset = 0;
  bool _autoScheduleEnabled = false;
  Map<int, String> _weekdayPresets = {}; // 1=пн..7=вс, значение это presetId
  List<BellSchedulePreset> _userPresets = [];

  String get currentPresetId => _currentPresetId;
  Map<int, LessonTime> get schedule => Map.unmodifiable(_schedule);
  int get timeOffset {
    if (usesServerTime) {
      return _bellTime.presets[effectivePresetId]?.offsetSeconds ?? 0;
    }
    if (supportsServerSync) return _manualOffsets[effectivePresetId] ?? 0;
    return _timeOffset;
  }

  bool get autoScheduleEnabled => _autoScheduleEnabled;
  Map<int, String> get weekdayPresets => Map.unmodifiable(_weekdayPresets);
  List<BellSchedulePreset> get userPresets => List.unmodifiable(_userPresets);

  /// встроенные пресеты вместе с пользовательскими
  List<BellSchedulePreset> get allPresets => [...presets, ..._userPresets];

  /// какой пресет активен прямо сейчас
  String get effectivePresetId {
    if (_autoScheduleEnabled) {
      final weekday =
          _bellTime.moscowNow.weekday; // в петербурге используется часовой пояс utc+3
      final pid = _weekdayPresets[weekday];
      if (pid != null) return pid;
    }
    return _currentPresetId;
  }

  Map<int, LessonTime> get _effectiveLessons {
    final eid = effectivePresetId;
    final serverPreset = usesServerFor(eid) ? _bellTime.presets[eid] : null;
    if (serverPreset != null) {
      return serverPreset.lessons.map(
        (number, time) =>
            MapEntry(number, LessonTime(start: time.start, end: time.end)),
      );
    }
    if (eid == 'custom') return _schedule;
    final preset = allPresets.firstWhere(
      (p) => p.id == eid,
      orElse: () =>
          BellSchedulePreset(id: 'custom', name: '', lessons: _schedule),
    );
    return preset.lessons;
  }

  static final List<BellSchedulePreset> presets = [
    const BellSchedulePreset(
      id: 'fml30_shevchenko',
      name: 'ФМЛ № 30',
      subtitle: 'ул. Шевченко, 23, корп.2',
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

  BellScheduleProvider({
    BellTimeService? bellTimeService,
    this.startTimers = true,
  }) : _bellTime = bellTimeService ?? BellTimeService() {
    if (startTimers) WidgetsBinding.instance.addObserver(this);
    ready = _loadSchedule();
  }

  Future<void> _loadSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    _currentPresetId = prefs.getString(_presetKey) ?? 'custom';
    _timeOffset = prefs.getInt(_offsetKey) ?? 0;
    _autoScheduleEnabled = prefs.getBool(_autoScheduleKey) ?? false;
    final corrections = prefs.getString(_correctionKey);
    if (corrections != null) {
      try {
        final data = jsonDecode(corrections) as Map<String, dynamic>;
        for (final id in BellTimeService.campusIds) {
          final setting = data[id] as Map<String, dynamic>?;
          _serverModes[id] = setting?['server'] as bool? ?? true;
          _manualOffsets[id] = setting?['offset'] as int? ?? 0;
        }
      } catch (_) {
        _serverModes.clear();
        _manualOffsets.clear();
      }
    } else if (BellTimeService.campusIds.contains(_currentPresetId)) {
      // старую поправку сохраняем только для ручного режима этого корпуса
      _manualOffsets[_currentPresetId] = _timeOffset;
      _timeOffset = 0;
    }

    final weekdayPresetsJson = prefs.getString(_weekdayPresetsKey);
    if (weekdayPresetsJson != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(weekdayPresetsJson);
        _weekdayPresets = data.map(
          (k, v) => MapEntry(int.parse(k), v as String),
        );
      } catch (_) {
        _weekdayPresets = {};
      }
    }

    final userPresetsJson = prefs.getString(_userPresetsKey);
    if (userPresetsJson != null) {
      try {
        final List<dynamic> data = jsonDecode(userPresetsJson);
        _userPresets = data
            .map((e) => BellSchedulePreset.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {
        _userPresets = [];
      }
    }

    final jsonStr = prefs.getString(_storageKey);
    if (jsonStr != null) {
      try {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        _schedule = data.map(
          (key, value) => MapEntry(
            int.parse(key),
            LessonTime.fromJson(value as Map<String, dynamic>),
          ),
        );
      } catch (e) {
        _schedule = Map.from(defaultSchedule);
      }
    } else {
      _schedule = Map.from(defaultSchedule);
    }
    await _bellTime.loadCache();
    if (_disposed) return;
    notifyListeners();
    await _saveCorrections();
    await _saveSchedule();
    await _syncTime();
  }

  Future<void> _syncTime() async {
    if (_disposed) return;
    if (!usesServerFor(_currentPresetId) &&
        !(_autoScheduleEnabled && _weekdayPresets.values.any(usesServerFor))) {
      _syncTimer?.cancel();
      _syncTimer = null;
      return;
    }
    if (startTimers) {
      _syncTimer ??= Timer.periodic(
        const Duration(minutes: 5),
        (_) => _syncTime(),
      );
    }
    await _bellTime.syncIfDue();
    if (!_disposed) notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(ready.then((_) => _syncTime()));
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _syncTimer?.cancel();
    if (startTimers) WidgetsBinding.instance.removeObserver(this);
    _bellTime.dispose();
    super.dispose();
  }

  Future<void> _saveCorrections() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _correctionKey,
      jsonEncode({
        for (final id in BellTimeService.campusIds)
          id: {
            'server': _serverModes[id] ?? true,
            'offset': _manualOffsets[id] ?? 0,
          },
      }),
    );
  }

  Future<void> setServerSync(bool enabled, {String? presetId}) async {
    final id = presetId ?? effectivePresetId;
    if (!BellTimeService.campusIds.contains(id)) return;
    _serverModes[id] = enabled;
    notifyListeners();
    await _saveCorrections();
    if (enabled) await _syncTime();
  }

  Future<void> _saveSchedule() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_presetKey, _currentPresetId);
    await prefs.setInt(_offsetKey, _timeOffset);

    final data = _schedule.map(
      (key, value) => MapEntry(key.toString(), value.toJson()),
    );
    await prefs.setString(_storageKey, jsonEncode(data));
  }

  Future<void> _saveUserPresets() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _userPresetsKey,
      jsonEncode(_userPresets.map((p) => p.toJson()).toList()),
    );
  }

  Future<void> _saveWeekdayPresets() async {
    final prefs = await SharedPreferences.getInstance();
    final data = _weekdayPresets.map((k, v) => MapEntry(k.toString(), v));
    await prefs.setString(_weekdayPresetsKey, jsonEncode(data));
  }

  LessonTime? getLessonTime(int lessonNum, {bool applyOffset = true}) {
    final baseTime = _effectiveLessons[lessonNum];
    if (baseTime == null) return null;

    final offset = timeOffset;
    if (!applyOffset || offset == 0) return baseTime;

    return LessonTime(
      start: TimeUtils.addSeconds(baseTime.start, offset),
      end: TimeUtils.addSeconds(baseTime.end, offset),
    );
  }

  Future<void> setTimeOffset(int seconds) async {
    if (supportsServerSync) {
      _serverModes[effectivePresetId] = false;
      _manualOffsets[effectivePresetId] = seconds;
      await _saveCorrections();
    } else {
      _timeOffset = seconds;
    }
    notifyListeners();
    await _saveSchedule();
  }

  Future<void> applyPreset(String presetId) async {
    final preset = allPresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () => BellSchedulePreset(
        id: 'custom',
        name: 'Своё',
        lessons: defaultSchedule,
      ),
    );

    _currentPresetId = presetId;
    _schedule = Map.from(preset.lessons);
    if (!BellTimeService.campusIds.contains(presetId)) {
      _timeOffset = preset.defaultOffset;
    }

    notifyListeners();
    await _saveSchedule();
    await _syncTime();
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

  // пользовательские пресеты

  Future<BellSchedulePreset> createUserPreset({
    required String name,
    String? subtitle,
    required Map<int, LessonTime> lessons,
  }) async {
    final id = 'user_${DateTime.now().millisecondsSinceEpoch}';
    final preset = BellSchedulePreset(
      id: id,
      name: name,
      subtitle: subtitle?.trim().isEmpty == true ? null : subtitle?.trim(),
      lessons: Map.from(lessons),
      isUserCreated: true,
    );
    _userPresets.add(preset);
    notifyListeners();
    await _saveUserPresets();
    return preset;
  }

  Future<void> updateUserPreset({
    required String id,
    required String name,
    String? subtitle,
    required Map<int, LessonTime> lessons,
  }) async {
    final idx = _userPresets.indexWhere((p) => p.id == id);
    if (idx == -1) return;
    _userPresets[idx] = BellSchedulePreset(
      id: id,
      name: name,
      subtitle: subtitle?.trim().isEmpty == true ? null : subtitle?.trim(),
      lessons: Map.from(lessons),
      isUserCreated: true,
    );
    // правим тот пресет, что сейчас на экране, значит и расписание надо обновить
    if (_currentPresetId == id) {
      _schedule = Map.from(lessons);
    }
    notifyListeners();
    await _saveUserPresets();
    if (_currentPresetId == id) await _saveSchedule();
  }

  Future<void> deleteUserPreset(String id) async {
    _userPresets.removeWhere((p) => p.id == id);
    // удаляем активный пресет, откатываемся на custom
    if (_currentPresetId == id) {
      _currentPresetId = 'custom';
      _schedule = Map.from(defaultSchedule);
      await _saveSchedule();
    }
    // и вычищаем его из дней недели
    final hadWeekday = _weekdayPresets.containsValue(id);
    _weekdayPresets.removeWhere((_, v) => v == id);
    notifyListeners();
    await _saveUserPresets();
    if (hadWeekday) await _saveWeekdayPresets();
  }

  // вспомогательное

  List<int> get sortedLessonNumbers {
    final numbers = _effectiveLessons.keys.toList();
    numbers.sort();
    return numbers;
  }

  String get currentPresetName {
    if (_currentPresetId == 'custom') return 'Своё расписание';
    final preset = allPresets.firstWhere(
      (p) => p.id == _currentPresetId,
      orElse: () => const BellSchedulePreset(
        id: '',
        name: 'Своё расписание',
        lessons: {},
      ),
    );
    return preset.subtitle != null
        ? '${preset.name} (${preset.subtitle})'
        : preset.name;
  }

  String get effectivePresetName {
    final eid = effectivePresetId;
    if (eid == 'custom') return 'Своё расписание';
    final preset = allPresets.firstWhere(
      (p) => p.id == eid,
      orElse: () => const BellSchedulePreset(
        id: '',
        name: 'Своё расписание',
        lessons: {},
      ),
    );
    return preset.subtitle != null
        ? '${preset.name} (${preset.subtitle})'
        : preset.name;
  }

  String presetNameForId(String presetId) {
    if (presetId == 'custom') return 'Своё расписание';
    final preset = allPresets.firstWhere(
      (p) => p.id == presetId,
      orElse: () =>
          const BellSchedulePreset(id: '', name: 'Неизвестно', lessons: {}),
    );
    return preset.subtitle != null
        ? '${preset.name} (${preset.subtitle})'
        : preset.name;
  }

  Future<void> setAutoScheduleEnabled(bool value) async {
    _autoScheduleEnabled = value;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_autoScheduleKey, value);
    await _syncTime();
  }

  Future<void> setWeekdayPreset(int weekday, String? presetId) async {
    if (presetId == null) {
      _weekdayPresets.remove(weekday);
    } else {
      _weekdayPresets[weekday] = presetId;
    }
    notifyListeners();
    await _saveWeekdayPresets();
    await _syncTime();
  }
}
