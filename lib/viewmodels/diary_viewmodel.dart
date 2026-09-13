import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../services/api_service.dart';
import '../services/lesson_teacher_cache.dart';
import '../services/marks_cache_service.dart';
import '../utils/html_content.dart';
import '../models/diary_models.dart';
import '../models/lesson_view_model.dart';
import '../models/lpart_models.dart';
import '../providers/bell_schedule_provider.dart';
import '../services/widget_data_service.dart';

class DiaryViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();
  final BellScheduleProvider bellScheduleProvider;

  List<DateTime> currentWeek = [];
  late DateTime selectedDate;
  Map<String, List<LessonViewModel>> lessons = {};
  bool isLoading = false;
  String? error;

  final LessonTeacherCache _teacherCache = LessonTeacherCache();
  int _loadGeneration = 0;
  String? _lessonOwner;

  String? get _owner => _api.userId == null || _api.currentPrsId == null
      ? null
      : '${_api.isDemo}_${_api.userId}_${_api.currentPrsId}';

  void _clearIdentityState() {
    _loadGeneration++;
    _lessonOwner = null;
    lessons.clear();
    isLoading = false;
    error = null;
    if (!_disposed) notifyListeners();
  }

  DiaryViewModel(
    this.bellScheduleProvider, {
    DateTime? initialDate,
    bool autoLoad = true,
  }) {
    selectedDate = initialDate ?? DateTime.now();
    _generateWeekSync(selectedDate);
    MarksCacheService().addListener(_clearIdentityState);
    if (autoLoad) loadSchedule();

    // расписание звонков могло поменяться, тогда пересчитываем время
    bellScheduleProvider.addListener(_onBellScheduleChanged);
  }

  void _onBellScheduleChanged() {
    // сдвиг поменялся, время уроков пересчитываем
    _refreshLessonTimes();
    _publishWidget();
    notifyListeners();
  }

  void _refreshLessonTimes() {
    // проставляем всем закэшированным урокам актуальное время из провайдера
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

  bool _disposed = false;

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    MarksCacheService().removeListener(_clearIdentityState);
    bellScheduleProvider.removeListener(_onBellScheduleChanged);
    super.dispose();
  }

  void _generateWeekSync(DateTime date) {
    final monday = DateUtils.dateOnly(date)
        .subtract(Duration(days: date.weekday - 1));
    currentWeek = List.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
  }

  void _generateWeek(DateTime date) {
    final monday = DateUtils.dateOnly(date)
        .subtract(Duration(days: date.weekday - 1));
    currentWeek = List.generate(
      7,
      (index) => monday.add(Duration(days: index)),
    );
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

    // группируем по номеру урока, в один слот их может попасть несколько
    final Map<int, List<LessonViewModel>> lessonMap = {};
    for (var lesson in sorted) {
      lessonMap.putIfAbsent(lesson.num, () => []).add(lesson);
    }

    // дыры ищем по уникальным номерам, а не по общему количеству,
    // иначе два урока в одном слоте всё сломают
    if (lastNum - firstNum + 1 == lessonMap.length) {
      return sorted;
    }

    final List<LessonViewModel> result = [];
    for (int num = firstNum; num <= lastNum; num++) {
      if (lessonMap.containsKey(num)) {
        result.addAll(lessonMap[num]!);
      } else {
        final times = bellScheduleProvider.getLessonTime(num);
        result.add(
          LessonViewModel.placeholder(
            num: num,
            startTime: times?.start ?? "",
            endTime: times?.end ?? "",
          ),
        );
      }
    }

    return result;
  }

  Future<void> loadSchedule({bool enrichHomework = true}) async {
    if (currentWeek.isEmpty || _disposed) return;
    final generation = ++_loadGeneration;
    final epoch = _api.identityEpoch;
    final initialOwner = _owner;
    bool current() =>
        !_disposed &&
        generation == _loadGeneration &&
        epoch == _api.identityEpoch &&
        (initialOwner == null || initialOwner == _owner);

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final startOfWeek = currentWeek.first;
      final endOfWeek = currentWeek.last.add(
        const Duration(hours: 23, minutes: 59, seconds: 59),
      );

      final d1 = startOfWeek.millisecondsSinceEpoch.toDouble();
      final d2 = endOfWeek.millisecondsSinceEpoch.toDouble();

      final json = await _api.getPrsDiary(d1, d2);
      if (!current()) return;
      final owner = _owner;
      bool owned() => current() && owner == _owner;
      final response = PrsDiaryResponse.fromJson(json);
      final teacherNames = await _teacherCache.resolve(
        response.lesson ?? [],
        owner: owner,
        isCurrent: owned,
      );
      if (!owned()) return;
      if (_lessonOwner != owner) lessons.clear();
      _lessonOwner = owner;
      for (
        var day = startOfWeek;
        !day.isAfter(endOfWeek);
        day = day.add(const Duration(days: 1))
      ) {
        lessons.remove(_dateKey(day));
      }
      _processResponse(response, teacherNames);
      _publishWidget();

      // дотягиваем домашнее задание из lpart
      if (enrichHomework) await _enrichWithLPart(startOfWeek, endOfWeek, owned);
      if (!owned()) return;
    } catch (e) {
      if (!current()) return;
      error = e.toString();
      debugPrint("Error loading schedule: $e");
    } finally {
      if (current()) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  void _publishWidget() {
    if (_lessonOwner == null || _lessonOwner != _owner) return;
    final today = DateUtils.dateOnly(DateTime.now());
    // просмотр другой недели не должен заменять сегодняшние данные виджета
    if (!currentWeek.any((day) => isSameDay(day, today))) return;
    WidgetDataService().updateScheduleWidget(
      lessons: getLessonsForDate(today),
      date: today,
      days: {
        for (final day in currentWeek)
          DateUtils.dateOnly(day): getLessonsForDate(day),
      },
    );
  }

  void _processResponse(
    PrsDiaryResponse response,
    Map<int, LessonTeacherNames> teacherNames,
  ) {
    final taskFormatter = DateFormat('yyyy-MM-dd');

    final Map<int, ({String val, String desc, int? partID})> marksMap = {};
    if (response.user != null) {
      for (var user in response.user!) {
        if (user.mark != null) {
          for (var m in user.mark!) {
            if (m.lessonID != null && m.value != null) {
              marksMap[m.lessonID!] = (
                val: m.value!,
                desc: m.partType ?? "Оценка",
                partID: m.partID,
              );
            }
          }
        }
      }
    }

    final Map<String, List<LessonViewModel>> batchLessons = {};

    if (response.lesson != null) {
      for (var raw in response.lesson!) {
        if (raw.date == null || raw.id == null) continue;

        final date = DateTime.fromMillisecondsSinceEpoch(raw.date!.toInt());
        final key = taskFormatter.format(date);

        String hwText = "";
        final hwHtml = <String>[];
        double? deadLine;
        double? markWeight;
        List<HomeworkFile> hwFiles = [];

        final markInfo = marksMap[raw.id];

        if (raw.part != null) {
          for (var part in raw.part!) {
            if (part.cat == "DZ" && part.variant != null) {
              for (var v in part.variant!) {
                if (v.text != null) {
                  // картинки из текста вытаскиваем как отдельные файлы
                  final imgRegex = RegExp(
                    r'<img\s[^>]*src="([^"]*)"',
                    caseSensitive: false,
                  );
                  int imgIndex = 1;
                  for (final match in imgRegex.allMatches(v.text!)) {
                    final imgUrl = match.group(1);
                    if (imgUrl != null) {
                      // fileId лежит в url вида /HWV_INLINE/{variantId}/{fileId}
                      final urlParts = imgUrl.split('/');
                      final fileIdStr = urlParts.isNotEmpty
                          ? urlParts.last.split('?').first
                          : '';
                      final fileId = int.tryParse(fileIdStr) ?? 0;
                      hwFiles.append(
                        HomeworkFile(
                          id: fileId,
                          name: 'Изображение $imgIndex.jpg',
                          variantId: v.id ?? 0,
                          url: imgUrl.split('?').first,
                        ),
                      );
                      imgIndex++;
                    }
                  }

                  if (v.text!.trim().isNotEmpty) {
                    hwHtml.add(v.text!);
                    hwText = hwHtml
                        .map(htmlToPlainText)
                        .where((text) => text.isNotEmpty)
                        .join('\n\n');
                    deadLine = v.deadLine;
                  }
                }
                if (v.file != null && v.id != null) {
                  for (var f in v.file!) {
                    if (f.id != null && f.fileName != null) {
                      hwFiles.append(
                        HomeworkFile(
                          id: f.id!,
                          name: f.fileName!,
                          variantId: v.id!,
                        ),
                      );
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
        final teacher = teacherNames[raw.id];

        final vm = LessonViewModel(
          id: raw.id!,
          num: num,
          subject: subjectName,
          topic: raw.subject ?? "",
          teacher: teacher?.short ?? raw.teacherShortName,
          teacherFull: teacher?.full ?? raw.teacherFullName,
          homework: hwText,
          homeworkHtml: hwHtml.isEmpty ? null : hwHtml.join("<br>"),
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

    lessons.addAll(batchLessons);
  }

  Future<void> _enrichWithLPart(
    DateTime startOfWeek,
    DateTime endOfWeek,
    bool Function() isCurrent,
  ) async {
    try {
      final yearId = await _api.getCurrentYearId();
      if (!isCurrent()) return;
      final begDate = startOfWeek.millisecondsSinceEpoch;
      final endDate = endOfWeek.millisecondsSinceEpoch;

      final lpartItems = await _api.getLPartListPupil(begDate, endDate, yearId);
      if (!isCurrent()) return;

      // раскладываем lpart по паре дата плюс предмет, чтобы быстро искать
      final taskFormatter = DateFormat('yyyy-MM-dd');
      final Map<String, List<LPartListItem>> lpartMap = {};
      for (final item in lpartItems) {
        if (item.passDt == null) continue;
        final date = DateTime.fromMillisecondsSinceEpoch(item.passDt!);
        final key = '${taskFormatter.format(date)}|${item.unitName ?? ''}';
        lpartMap.putIfAbsent(key, () => []).add(item);
      }

      // подмешиваем к урокам partId, attachCnt и превью, если его не хватало
      lessons.forEach((dateKey, lessonList) {
        for (int i = 0; i < lessonList.length; i++) {
          final lesson = lessonList[i];
          if (lesson.isPlaceholder) continue;

          final lookupKey = '$dateKey|${lesson.subject}';
          final lparts = lpartMap[lookupKey];
          if (lparts == null || lparts.isEmpty) continue;

          final candidates = lparts
              .where(
                (lp) =>
                    (lp.preview ?? '').isNotEmpty || (lp.attachCnt ?? 0) > 0,
              )
              .toList();
          if (candidates.isEmpty) continue;

          // берём тех, у кого есть partId, детали и файлы тянутся именно по нему
          final candidate = candidates.firstWhere(
            (lp) => lp.partId != null,
            orElse: () => candidates.first,
          );

          final shouldUpdateHomeworkText =
              lesson.homework.isEmpty && (candidate.preview ?? '').isNotEmpty;
          final nextHomework = shouldUpdateHomeworkText
              ? (candidate.preview ?? '')
              : lesson.homework;

          final nextPartId = lesson.homeworkPartId ?? candidate.partId;
          final currentAttachCount = lesson.homeworkAttachCount ?? 0;
          final nextAttachCount = currentAttachCount > 0
              ? lesson.homeworkAttachCount
              : candidate.attachCnt;

          // трогаем урок, только если реально узнали что то новое
          final changed =
              (shouldUpdateHomeworkText) ||
              (nextPartId != null && nextPartId != lesson.homeworkPartId) ||
              ((nextAttachCount ?? 0) != currentAttachCount);
          if (!changed) continue;

          lessonList[i] = lesson.copyWith(
            homework: nextHomework,
            homeworkPartId: nextPartId,
            homeworkAttachCount: nextAttachCount,
          );
        }
      });
    } catch (e) {
      // lpart не подтянулся, не страшно
      debugPrint("LPart enrichment failed: $e");
    }
  }
}

extension ListExtensions<E> on List<E> {
  void append(E element) => add(element);
}
