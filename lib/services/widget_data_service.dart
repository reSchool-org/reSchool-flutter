import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/widget_models.dart';
import '../models/lesson_view_model.dart';
import '../models/homework_models.dart';
import '../utils/html_content.dart';
import '../utils/time_utils.dart';
import '../providers/bell_schedule_provider.dart';

/// записываем снимки и обновляем виджеты по очереди, сброс аккаунта отменяет ожидающие записи
class WidgetDataService {
  static final WidgetDataService _instance = WidgetDataService._();
  factory WidgetDataService() => _instance;
  WidgetDataService._() : _platform = _nativePlatform, _now = DateTime.now;

  @visibleForTesting
  WidgetDataService.forTesting(this._platform, {DateTime Function()? now})
    : _now = now ?? DateTime.now;

  static TargetPlatform get _nativePlatform {
    if (!kIsWeb) {
      if (Platform.isIOS) return TargetPlatform.iOS;
      if (Platform.isAndroid) return TargetPlatform.android;
      if (Platform.isMacOS) return TargetPlatform.macOS;
    }
    return TargetPlatform.linux;
  }

  final TargetPlatform _platform;
  final DateTime Function() _now;
  static const _channel = MethodChannel('com.magisky.reschoolbeta/widgets');
  static const _kinds = ['ScheduleWidget', 'HomeworkWidget', 'GradesWidget'];
  final Map<String, String> _published = {};
  final Map<DateTime, Map<String, dynamic>> _scheduleDays = {};
  Future<void> _pending = Future.value();
  Future<void>? _initialization;
  int _generation = 0;
  WidgetConfig? _lastConfiguration;
  Object? lastError;

  bool get isSupported =>
      !kIsWeb &&
      {
        TargetPlatform.iOS,
        TargetPlatform.android,
        TargetPlatform.macOS,
      }.contains(_platform);

  Future<void> initialize() async {
    try {
      await _ensureInitialized();
    } catch (error) {
      lastError = error;
      debugPrint('Widget initialization failed: $error');
    }
  }

  Future<void> _ensureInitialized() {
    if (!isSupported) return Future.value();
    return _initialization ??= _initialize().catchError((Object error) {
      _initialization = null;
      throw error;
    });
  }

  Future<void> _initialize() async {
    await initializeDateFormatting('ru');
    if (_platform == TargetPlatform.iOS) {
      await HomeWidget.setAppGroupId(WidgetDataKeys.appGroup);
    }
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(WidgetDataKeys.widgetConfig);
    WidgetConfig config;
    try {
      config = raw == null
          ? WidgetConfig()
          : WidgetConfig.fromJson(jsonDecode(raw));
    } catch (_) {
      config = WidgetConfig();
    }
    await _save(WidgetDataKeys.widgetConfig, jsonEncode(config.toJson()));
    _lastConfiguration = config;
  }

  Future<void> _enqueue(Future<void> Function() operation) {
    if (!isSupported) return Future.value();
    final generation = _generation;
    final result = _pending
        .then((_) async {
          if (generation != _generation) return;
          await _ensureInitialized();
          if (generation != _generation) return;
          await operation();
        })
        .catchError((Object error) {
          lastError = error;
          debugPrint('Widget publication failed: $error');
        });
    _pending = result;
    return result;
  }

  Future<void> _save(String key, String data) async {
    final bool? saved;
    if (_platform == TargetPlatform.macOS) {
      saved = await _channel.invokeMethod<bool>('saveWidgetData', {
        'key': key,
        'data': data,
      });
    } else {
      saved = await HomeWidget.saveWidgetData<String>(key, data);
    }
    if (saved == false) throw StateError('Could not save $key');
  }

  Future<void> _reload(WidgetType type) async {
    final kind = _kinds[type.index];
    if (_platform == TargetPlatform.macOS) {
      await _channel.invokeMethod('reloadWidget', {'kind': kind});
    } else {
      final updated = await HomeWidget.updateWidget(
        androidName: 'widgets.$kind',
        iOSName: kind,
      );
      if (updated == false) throw StateError('Could not reload $kind');
    }
  }

  Future<void> _publish(
    WidgetType type,
    String key,
    Map<String, dynamic> Function() build,
  ) => _enqueue(() async {
    final data = build();
    // изменение одной метки времени не должно расходовать лимит обновлений widgetkit
    final content = jsonEncode(data);
    if (_published[key] == content) return;
    await _save(
      key,
      jsonEncode({...data, 'lastUpdated': _now().toIso8601String()}),
    );
    await _reload(type);
    // ДЗ использует время окончания школы из снимка расписания.
    if (type == WidgetType.schedule) await _reload(WidgetType.homework);
    if (_platform == TargetPlatform.android &&
        type != WidgetType.grades &&
        await hasInstalledWidgets()) {
      final now = _now();
      final horizon = DateTime(now.year, now.month, now.day + 15);
      final updates = <int>{
        for (var i = 1; i <= 15; i++)
          DateTime(now.year, now.month, now.day + i).millisecondsSinceEpoch,
        for (final day in _scheduleDays.values)
          for (final field in ['dayStartMs', 'schoolEndMs'])
            if (day[field] is int &&
                (day[field] as int) > now.millisecondsSinceEpoch &&
                (day[field] as int) <= horizon.millisecondsSinceEpoch)
              day[field] as int,
      }.toList()..sort();
      for (final target
          in type == WidgetType.schedule
              ? [WidgetType.schedule, WidgetType.homework]
              : [type]) {
        await HomeWidget.scheduleWidgetUpdates(
          updates.map(DateTime.fromMillisecondsSinceEpoch).toList(),
          androidName: 'widgets.${_kinds[target.index]}',
        );
      }
    }
    _published[key] = content;
  });

  Map<String, dynamic> _scheduleDay(
    List<LessonViewModel> lessons,
    DateTime date,
    BellScheduleProvider? bells,
  ) {
    final sorted = lessons.where((l) => !l.isPlaceholder).toList()
      ..sort((a, b) => a.num.compareTo(b.num));
    final rows = sorted.map((lesson) {
      final time = bells?.getLessonTime(lesson.num, date: date);
      return WidgetLesson(
        num: lesson.num,
        subject: lesson.subject,
        teacher: lesson.teacher,
        startTime: time?.start ?? lesson.startTime,
        endTime: time?.end ?? lesson.endTime,
        mark: lesson.mark,
      ).toJson();
    }).toList();
    final lastEnd = TimeUtils.lastLessonEnd(
      rows.map((l) => l['endTime'] as String),
    );
    DateTime instant(int seconds) =>
        bells?.deviceTimeForDate(date, seconds: seconds) ??
        DateTime(date.year, date.month, date.day, 0, 0, seconds);
    return {
      'date': DateFormat('d MMMM', 'ru').format(date),
      'dateISO': DateFormat('yyyy-MM-dd').format(date),
      'dayStartMs': instant(0).millisecondsSinceEpoch,
      'dayEndMs': instant(86400).millisecondsSinceEpoch,
      'schoolEndMs': lastEnd == null
          ? null
          : instant(lastEnd).millisecondsSinceEpoch,
      'lessons': rows,
    };
  }

  Future<void> updateScheduleWidget({
    required List<LessonViewModel> lessons,
    required DateTime date,
    Map<DateTime, List<LessonViewModel>>? days,
    BellScheduleProvider? bells,
  }) {
    // Снимок содержит реальные моменты последних звонков, включая поправку часов.
    // Будущим дням назначаем их собственное расписание звонков.
    final lessonSnapshot = List<LessonViewModel>.of(lessons);
    final week = days?.map(
      (key, value) => MapEntry(
        DateTime(key.year, key.month, key.day),
        List<LessonViewModel>.of(value),
      ),
    );
    return _publish(WidgetType.schedule, WidgetDataKeys.scheduleData, () {
      final snapshot = _scheduleDay(lessonSnapshot, date, bells);
      if (week != null) {
        _scheduleDays.addAll(
          week.map(
            (key, value) => MapEntry(key, _scheduleDay(value, key, bells)),
          ),
        );
      }
      _scheduleDays[DateTime(date.year, date.month, date.day)] = snapshot;
      final now = _now().millisecondsSinceEpoch;
      final limit = _now().add(const Duration(days: 366));
      _scheduleDays.removeWhere(
        (key, day) => (day['dayEndMs'] as int) <= now || key.isAfter(limit),
      );
      final dates = _scheduleDays.keys.toList()..sort();
      return {
        ...snapshot,
        'days': dates.map((day) => _scheduleDays[day]!).toList(),
      };
    });
  }

  Future<void> updateHomeworkWidget({
    required List<HomeworkItem> items,
    int maxItems = 20,
  }) {
    final snapshot = List<HomeworkItem>.of(items);
    return _publish(WidgetType.homework, WidgetDataKeys.homeworkData, () {
      final today = DateUtils.dateOnly(_now());
      final sorted =
          snapshot
              .where((item) => !DateUtils.dateOnly(item.date).isBefore(today))
              .toList()
            ..sort((a, b) => a.date.compareTo(b.date));
      final seen = <String>{};
      final perDay = <String, int>{};
      final result = <Map<String, dynamic>>[];
      for (final item in sorted) {
        final text = htmlToPlainText(item.html ?? item.text)
            .replaceAll(RegExp(r'\s+'), ' ')
            .trim();
        final dateISO = DateFormat('yyyy-MM-dd').format(item.date);
        final identity = '$dateISO|${item.subject}|$text|${item.partId ?? ''}';
        if (!seen.add(identity)) continue;
        // Сегодняшние задания не должны вытеснять завтрашние из кеша.
        if ((perDay[dateISO] ?? 0) >= maxItems.clamp(1, 100)) continue;
        perDay[dateISO] = (perDay[dateISO] ?? 0) + 1;
        final deadline = item.deadline;
        // даты дневника приходят в миллисекундах, старые значения в секундах тоже принимаем
        final deadlineDate =
            deadline != null &&
                deadline.isFinite &&
                deadline > 0 &&
                deadline < 8640000000000000
            ? DateTime.fromMillisecondsSinceEpoch(
                (deadline < 100000000000 ? deadline * 1000 : deadline).toInt(),
              )
            : null;
        result.add({
          ...WidgetHomeworkItem(
            subject: item.subject,
            text: text.characters.length > 240
                ? '${text.characters.take(239)}…'
                : text,
            date: DateFormat('d MMM', 'ru').format(item.date),
            deadline: deadlineDate == null
                ? null
                : DateFormat('d MMM HH:mm', 'ru').format(deadlineDate),
            hasFiles: item.files.isNotEmpty || (item.attachCount ?? 0) > 0,
          ).toJson(),
          'dateISO': dateISO,
        });
      }
      return {'items': result};
    });
  }

  Future<void> updateGradesWidget({
    required List<WidgetGrade> grades,
    required String periodName,
  }) {
    // Сначала предметы с большим числом оценок за выбранный период.
    // При равенстве сохраняем исходный порядок, чтобы строки не прыгали.
    final ordered = grades.asMap().entries.toList()
      ..sort((a, b) {
        final byCount = (b.value.totalMarks ?? 0).compareTo(
          a.value.totalMarks ?? 0,
        );
        return byCount != 0 ? byCount : a.key.compareTo(b.key);
      });
    final snapshot = ordered.map((entry) => entry.value.toJson()).toList();
    return _publish(
      WidgetType.grades,
      WidgetDataKeys.gradesData,
      () => {'periodName': periodName, 'grades': snapshot},
    );
  }

  Future<void> updateConfiguration(WidgetConfig config) => _enqueue(() async {
    final previous = _lastConfiguration;
    await _save(WidgetDataKeys.widgetConfig, jsonEncode(config.toJson()));
    if (previous == null ||
        previous.scheduleEnabled != config.scheduleEnabled ||
        previous.showTeacherInSchedule != config.showTeacherInSchedule) {
      await _reload(WidgetType.schedule);
    }
    if (previous == null ||
        previous.homeworkEnabled != config.homeworkEnabled ||
        previous.homeworkItemsCount != config.homeworkItemsCount ||
        previous.showDeadlineInHomework != config.showDeadlineInHomework) {
      await _reload(WidgetType.homework);
    }
    if (previous == null ||
        previous.gradesEnabled != config.gradesEnabled ||
        previous.gradesSubjectsCount != config.gradesSubjectsCount) {
      await _reload(WidgetType.grades);
    }
    _lastConfiguration = config;
  });

  Future<void> updateAppearance({
    required Color accent,
    required ThemeMode mode,
  }) {
    Map<String, int> palette(Brightness brightness) {
      final colors = ColorScheme.fromSeed(
        seedColor: accent,
        brightness: brightness,
      );
      return {
        'background': colors.surface.toARGB32(),
        'surface': colors.surfaceContainer.toARGB32(),
        'text': colors.onSurface.toARGB32(),
        'secondary': colors.onSurfaceVariant.toARGB32(),
        'accent': colors.primary.toARGB32(),
      };
    }

    final data = jsonEncode({
      'mode': mode.name,
      'light': palette(Brightness.light),
      'dark': palette(Brightness.dark),
    });
    return _enqueue(() async {
      if (_published['widget_appearance'] == data) return;
      await _save('widget_appearance', data);
      for (final type in WidgetType.values) {
        await _reload(type);
      }
      _published['widget_appearance'] = data;
    });
  }

  /// перерисовываем сохранённые снимки, за обновление по сети отвечает WidgetSyncService
  Future<void> flush() => _pending;

  Future<bool> hasInstalledWidgets() async {
    if (!isSupported) return false;
    if (_platform == TargetPlatform.macOS) return true;
    try {
      return (await HomeWidget.getInstalledWidgets()).isNotEmpty;
    } catch (_) {
      return true;
    }
  }

  Future<void> updateAllWidgets() => _enqueue(() async {
    for (final type in WidgetType.values) {
      await _reload(type);
    }
  });

  Future<void> clearAllWidgetData() {
    _generation++;
    _published.clear();
    _scheduleDays.clear();
    return _enqueue(() async {
      await _save(
        WidgetDataKeys.scheduleData,
        jsonEncode({'date': '', 'lessons': [], 'lastUpdated': ''}),
      );
      await _save(
        WidgetDataKeys.homeworkData,
        jsonEncode({'items': [], 'lastUpdated': ''}),
      );
      await _save(
        WidgetDataKeys.gradesData,
        jsonEncode({'periodName': '', 'grades': [], 'lastUpdated': ''}),
      );
      _published.clear();
      _scheduleDays.clear();
      if (_platform == TargetPlatform.android) {
        for (final kind in _kinds.take(2)) {
          await HomeWidget.cancelScheduledWidgetUpdates(
            androidName: 'widgets.$kind',
          );
        }
      }
      for (final type in WidgetType.values) {
        await _reload(type);
      }
    });
  }
}
