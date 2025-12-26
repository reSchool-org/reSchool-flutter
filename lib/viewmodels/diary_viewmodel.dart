import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import '../services/api_service.dart';
import '../models/diary_models.dart';
import '../models/lesson_view_model.dart';
import '../providers/bell_schedule_provider.dart';
import '../services/widget_data_service.dart';

class DiaryViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();
  final BellScheduleProvider bellScheduleProvider;

  List<DateTime> currentWeek = [];
  DateTime selectedDate = DateTime.now();
  Map<String, List<LessonViewModel>> lessons = {};
  bool isLoading = false;
  String? error;

  final Map<String, ({String short, String full})> _teacherCache = {};
  static const String _teacherCacheKey = 'diary_teacher_cache';

  DiaryViewModel(this.bellScheduleProvider) {
    _generateWeekSync(selectedDate);
    _init();

    bellScheduleProvider.addListener(_onBellScheduleChanged);
  }

  void _onBellScheduleChanged() {
    _refreshLessonTimes();
    notifyListeners();
  }

  void _refreshLessonTimes() {
    lessons.forEach((key, lessonList) {
      for (int i = 0; i < lessonList.length; i++) {
        final lesson = lessonList[i];
        final times = bellScheduleProvider.getLessonTime(lesson.num);
        if (times != null) {
          lessonList[i] = lesson.copyWith(
            startTime: times.start,
            endTime: times.end,
          );
        }
      }
    });
  }

  @override
  void dispose() {
    bellScheduleProvider.removeListener(_onBellScheduleChanged);
    super.dispose();
  }

  void _generateWeekSync(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    currentWeek = List.generate(7, (index) => monday.add(Duration(days: index)));
  }

  Future<void> _init() async {
    await _loadTeacherCache();
    loadSchedule();
  }

  Future<void> _loadTeacherCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonStr = prefs.getString(_teacherCacheKey);
      if (jsonStr != null) {
        final Map<String, dynamic> data = jsonDecode(jsonStr);
        data.forEach((key, value) {
          _teacherCache[key] = (short: value['short'] as String, full: value['full'] as String);
        });
      }
    } catch (e) {
      print("Error loading teacher cache: $e");
    }
  }

  Future<void> _saveTeacherCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final Map<String, dynamic> data = {};
      _teacherCache.forEach((key, value) {
        data[key] = {'short': value.short, 'full': value.full};
      });
      await prefs.setString(_teacherCacheKey, jsonEncode(data));
    } catch (e) {
      print("Error saving teacher cache: $e");
    }
  }

  void _generateWeek(DateTime date) {
    final monday = date.subtract(Duration(days: date.weekday - 1));
    currentWeek = List.generate(7, (index) => monday.add(Duration(days: index)));
    notifyListeners();
  }

  void changeWeek(int offset) {
    selectedDate = selectedDate.add(Duration(days: offset * 7));
    _generateWeek(selectedDate);
    loadSchedule();
  }

  void selectDate(DateTime date) {
    selectedDate = date;

    if (!currentWeek.any((d) => isSameDay(d, date))) {
      _generateWeek(date);
      loadSchedule();
    } else {
      notifyListeners();
    }
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }

  String _dateKey(DateTime date) {
    return DateFormat('yyyy-MM-dd').format(date);
  }

  List<LessonViewModel> getLessonsForSelectedDate() {
    return getLessonsForDate(selectedDate);
  }

  List<LessonViewModel> getLessonsForDate(DateTime date) {
    final rawLessons = lessons[_dateKey(date)] ?? [];
    if (rawLessons.isEmpty) return [];

    return _fillLessonGaps(rawLessons);
  }

  List<LessonViewModel> _fillLessonGaps(List<LessonViewModel> rawLessons) {
    if (rawLessons.isEmpty) return [];

    final sorted = List<LessonViewModel>.from(rawLessons)
      ..sort((a, b) => a.num.compareTo(b.num));

    final firstNum = sorted.first.num;
    final lastNum = sorted.last.num;

    if (lastNum - firstNum + 1 == sorted.length) {
      return sorted;
    }

    final Map<int, LessonViewModel> lessonMap = {
      for (var lesson in sorted) lesson.num: lesson
    };

    final List<LessonViewModel> result = [];
    for (int num = firstNum; num <= lastNum; num++) {
      if (lessonMap.containsKey(num)) {
        result.add(lessonMap[num]!);
      } else {
        final times = bellScheduleProvider.getLessonTime(num);
        result.add(LessonViewModel.placeholder(
          num: num,
          startTime: times?.start ?? "",
          endTime: times?.end ?? "",
        ));
      }
    }

    return result;
  }

  Future<void> loadSchedule() async {
    if (currentWeek.isEmpty) return;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final startOfWeek = currentWeek.first;
      final endOfWeek = currentWeek.last.add(const Duration(hours: 23, minutes: 59, seconds: 59));

      final d1 = startOfWeek.millisecondsSinceEpoch.toDouble();
      final d2 = endOfWeek.millisecondsSinceEpoch.toDouble();

      final json = await _api.getPrsDiary(d1, d2);
      final response = PrsDiaryResponse.fromJson(json);

      _processResponse(response);

      WidgetDataService().updateScheduleWidget(
        lessons: getLessonsForSelectedDate(),
        date: selectedDate,
      );

    } catch (e) {
      error = e.toString();
      print("Error loading schedule: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  void _processResponse(PrsDiaryResponse response) {
    final taskFormatter = DateFormat('yyyy-MM-dd');

    final Map<int, ({String val, String desc, int? partID})> marksMap = {};
    if (response.user != null) {
      for (var user in response.user!) {
        if (user.mark != null) {
          for (var m in user.mark!) {
            if (m.lessonID != null && m.value != null) {
              marksMap[m.lessonID!] = (val: m.value!, desc: m.partType ?? "Оценка", partID: m.partID);
            }
          }
        }
      }
    }

    bool cacheUpdated = false;
    if (response.lesson != null) {
      for (var raw in response.lesson!) {
        final subjectName = raw.unit?.name;
        final teacher = raw.teacher;

        if (subjectName != null && teacher != null) {
          final short = teacher.shortName;

          if (short.isNotEmpty && !_teacherCache.containsKey(subjectName)) {
            _teacherCache[subjectName] = (short: short, full: teacher.fullName);
            cacheUpdated = true;
          }
        }
      }
    }

    if (cacheUpdated) {
      _saveTeacherCache();
    }

    final Map<String, List<LessonViewModel>> batchLessons = {};

    if (response.lesson != null) {
      for (var raw in response.lesson!) {
        if (raw.date == null || raw.id == null) continue;

        final date = DateTime.fromMillisecondsSinceEpoch(raw.date!.toInt());
        final key = taskFormatter.format(date);

        String hwText = "";
        double? deadLine;
        double? markWeight;
        List<HomeworkFile> hwFiles = [];

        final markInfo = marksMap[raw.id];

        if (raw.part != null) {
          for (var part in raw.part!) {
            if (part.cat == "DZ" && part.variant != null) {
              for (var v in part.variant!) {
                if (v.text != null) {
                  final clean = v.text!.replaceAll(RegExp(r'<[^>]*>'), '').trim();
                  if (clean.isNotEmpty) {
                    hwText = clean;
                    deadLine = v.deadLine;
                  }
                }
                if (v.file != null && v.id != null) {
                  for (var f in v.file!) {
                    if (f.id != null && f.fileName != null) {
                      hwFiles.append(HomeworkFile(id: f.id!, name: f.fileName!, variantId: v.id!));
                    }
                  }
                }
              }
            }

            if (markInfo?.partID != null) {
               if (part.mrkWt != null) {
                 markWeight = part.mrkWt;
               }
            }
          }
        }

        final num = raw.numInDay ?? 0;
        final times = bellScheduleProvider.getLessonTime(num);
        final startTime = times?.start ?? "";
        final endTime = times?.end ?? "";

        final subjectName = raw.unit?.name ?? "Предмет";
        var tShort = raw.teacher?.shortName ?? "";
        var tFull = raw.teacher?.fullName ?? "";

        if (tShort.isEmpty || tShort == "Учитель") {
          if (_teacherCache.containsKey(subjectName)) {
            tShort = _teacherCache[subjectName]!.short;
            tFull = _teacherCache[subjectName]!.full;
          }
        }

        final vm = LessonViewModel(
          id: raw.id!,
          num: num,
          subject: subjectName,
          topic: raw.subject ?? "",
          teacher: tShort,
          teacherFull: tFull,
          homework: hwText,
          homeworkDeadline: deadLine,
          homeworkFiles: hwFiles,
          mark: markInfo?.val,
          markDescription: markInfo?.desc,
          markWeight: markWeight,
          startTime: startTime,
          endTime: endTime,
        );

        if (batchLessons[key] == null) {
          batchLessons[key] = [];
        }
        batchLessons[key]!.add(vm);
      }
    }

    batchLessons.forEach((key, list) {
      list.sort((a, b) => a.num.compareTo(b.num));
    });

    _updateCachedLessonsWithTeachers();

    lessons.addAll(batchLessons);
  }

  void _updateCachedLessonsWithTeachers() {
    lessons.forEach((key, lessonList) {
      for (int i = 0; i < lessonList.length; i++) {
        final lesson = lessonList[i];
        if (lesson.teacher.isEmpty && _teacherCache.containsKey(lesson.subject)) {
          lessonList[i] = lesson.copyWith(
            teacher: _teacherCache[lesson.subject]!.short,
            teacherFull: _teacherCache[lesson.subject]!.full,
          );
        }
      }
    });
  }
}

extension ListExtensions<E> on List<E> {
  void append(E element) => add(element);
}