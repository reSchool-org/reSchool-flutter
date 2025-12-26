import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/marks_models.dart';
import '../models/lesson_view_model.dart';
import '../models/widget_models.dart';
import '../services/api_service.dart';
import '../providers/bell_schedule_provider.dart';
import '../services/widget_data_service.dart';

class MarksViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();
  final BellScheduleProvider bellScheduleProvider;

  List<PeriodSelectionItem> allPeriods = [];
  PeriodSelectionItem? selectedPeriod;
  List<SubjectData> subjects = [];

  bool isLoading = false;
  bool isRefreshing = false;
  String? error;
  DateTime? lastUpdated;

  final Map<String, List<VirtualMark>> _virtualMarks = {};
  final Set<String> _deletedMarkIds = {};

  static const String _savedPeriodKey = "lastSelectedPeriodId";
  static const String _cachePrefix = "marks_cache_";
  static const String _cacheTimePrefix = "marks_cache_time_";
  static const Duration _cacheExpiry = Duration(days: 1);

  MarksViewModel(this.bellScheduleProvider);

  Future<void> loadPeriods() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final groupsJson = await _api.getClassByUser();
      final groups = groupsJson.map((e) => GroupResponse.fromJson(e)).toList();

      groups.sort((a, b) => (b.begDate ?? 0).compareTo(a.begDate ?? 0));

      final filterPrefs = await SharedPreferences.getInstance();
      if (filterPrefs.getBool('display_only_current_class') ?? false) {
        if (groups.isNotEmpty) {
          final first = groups.first;
          groups.clear();
          groups.add(first);
        }
      }

      List<PeriodSelectionItem> items = [];

      for (var group in groups) {
        if (group.groupId == null) continue;

        final periodsJson = await _api.getPeriods(group.groupId!);
        final rootPeriod = PeriodResponse.fromJson(periodsJson);

        if (rootPeriod.items != null) {
          final flat = _flattenPeriods(rootPeriod.items!, 0);
          items.addAll(flat.map((p) => PeriodSelectionItem(
            period: p.period,
            groupId: group.groupId!,
            groupName: group.groupName ?? "Group ${group.groupId}",
            depth: p.depth,
          )));
        }
      }

      allPeriods = items;

      final prefs = await SharedPreferences.getInstance();
      final savedId = prefs.getInt(_savedPeriodKey);

      if (savedId != null && savedId != 0) {
        try {
          selectedPeriod = allPeriods.firstWhere((p) => p.period.id == savedId);
        } catch (_) {
        }
      }

      if (selectedPeriod == null) {
        final now = DateTime.now().millisecondsSinceEpoch.toDouble();
        try {
          selectedPeriod = allPeriods.firstWhere((item) {
            final d1 = item.period.date1;
            final d2 = item.period.date2;
            return d1 != null && d2 != null && now >= d1 && now <= d2;
          });
        } catch (_) {
          if (allPeriods.isNotEmpty) selectedPeriod = allPeriods.first;
        }
      }

      if (selectedPeriod != null) {
        await loadMarksData();
      }

    } catch (e) {
      error = e.toString();
      print("Error loading periods: $e");
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  List<({PeriodResponse period, int depth})> _flattenPeriods(List<PeriodResponse> periods, int depth) {
    List<({PeriodResponse period, int depth})> result = [];

    periods.sort((a, b) => (a.date1 ?? 0).compareTo(b.date1 ?? 0));

    for (var p in periods) {
      final code = p.typeCode ?? "";

      final isValid = code == "Q" || code == "HY" || code == "Y";

      if (isValid) {
        result.add((period: p, depth: depth));
      }

      if (p.items != null) {
        final nextDepth = isValid ? depth + 1 : depth;
        result.addAll(_flattenPeriods(p.items!, nextDepth));
      }
    }
    return result;
  }

  void selectPeriod(PeriodSelectionItem item) {
    selectedPeriod = item;
    if (item.period.id != null) {
      SharedPreferences.getInstance().then((prefs) {
        prefs.setInt(_savedPeriodKey, item.period.id!);
      });
    }
    loadMarksData();
  }

  Future<void> refreshMarksData() async {
    if (selectedPeriod == null || selectedPeriod!.period.id == null) return;

    isRefreshing = true;
    notifyListeners();

    await _fetchAndCacheMarksData(forceRefresh: true);

    isRefreshing = false;
    notifyListeners();
  }

  Future<void> loadMarksData() async {
    if (selectedPeriod == null || selectedPeriod!.period.id == null) return;

    isLoading = true;
    error = null;
    notifyListeners();

    await _fetchAndCacheMarksData(forceRefresh: false);

    isLoading = false;
    notifyListeners();
  }

  Future<void> _fetchAndCacheMarksData({required bool forceRefresh}) async {
    final periodId = selectedPeriod!.period.id!;
    final cacheKey = "$_cachePrefix$periodId";
    final cacheTimeKey = "$_cacheTimePrefix$periodId";

    try {
      final prefs = await SharedPreferences.getInstance();

      if (!forceRefresh) {
        final cachedData = prefs.getString(cacheKey);
        final cachedTimeMs = prefs.getInt(cacheTimeKey);

        if (cachedData != null && cachedTimeMs != null) {
          final cachedTime = DateTime.fromMillisecondsSinceEpoch(cachedTimeMs);
          final age = DateTime.now().difference(cachedTime);

          if (age < _cacheExpiry) {
            _loadFromCache(cachedData);
            lastUpdated = cachedTime;
            print("Loaded marks from cache (age: ${age.inMinutes} min)");

            final widgetGrades = subjects.map((s) => WidgetGrade(
              subject: s.name,
              average: s.average,
              rating: s.rating,
            )).toList();

            WidgetDataService().updateGradesWidget(
              grades: widgetGrades,
              periodName: selectedPeriod?.period.name ?? "Период",
            );
            return;
          }
        }
      }

      final d1 = selectedPeriod!.period.date1 ?? 0;
      final d2 = selectedPeriod!.period.date2 ?? 0;

      final unitsJson = await _api.getDiaryUnits(periodId);
      final unitsResponse = DiaryUnitResponse.fromJson(unitsJson);

      final diaryJson = await _api.getDiaryPeriod(periodId);
      final diaryResponse = DiaryPeriodResponse.fromJson(diaryJson);

      final prsDiaryJson = await _api.getPrsDiary(d1, d2);
      final homeworkMap = _extractHomeworkFromPrsDiary(prsDiaryJson);

      _processMarksFromPeriod(unitsResponse, diaryResponse, homeworkMap);

      final cacheData = _serializeSubjects();
      await prefs.setString(cacheKey, cacheData);
      await prefs.setInt(cacheTimeKey, DateTime.now().millisecondsSinceEpoch);
      lastUpdated = DateTime.now();

      print("Marks data fetched and cached");

      final widgetGrades = subjects.map((s) => WidgetGrade(
        subject: s.name,
        average: s.average,
        rating: s.rating,
      )).toList();

      WidgetDataService().updateGradesWidget(
        grades: widgetGrades,
        periodName: selectedPeriod?.period.name ?? "Период",
      );

    } catch (e) {
      error = e.toString();
      print("Error loading marks data: $e");
    }
  }

  String _serializeSubjects() {
    final list = subjects.map((s) => {
      'id': s.id,
      'name': s.name,
      'average': s.average,
      'totalMark': s.totalMark,
      'teacher': s.teacher,
      'rating': s.rating,
      'marks': s.marks.map((m) => {
        'value': m.value,
        'date': m.date.millisecondsSinceEpoch,
        'lesson': {
          'id': m.lesson.id,
          'num': m.lesson.num,
          'subject': m.lesson.subject,
          'topic': m.lesson.topic,
          'teacher': m.lesson.teacher,
          'teacherFull': m.lesson.teacherFull,
          'homework': m.lesson.homework,
          'startTime': m.lesson.startTime,
          'endTime': m.lesson.endTime,
          'mark': m.lesson.mark,
          'markDescription': m.lesson.markDescription,
          'markWeight': m.lesson.markWeight,
        },
      }).toList(),
    }).toList();
    return jsonEncode(list);
  }

  void _loadFromCache(String cacheData) {
    try {
      final List<dynamic> list = jsonDecode(cacheData);
      subjects = list.map((s) {
      final marks = (s['marks'] as List<dynamic>).map((m) {
        final lessonData = m['lesson'] as Map<String, dynamic>;
        return MarkData(
          value: m['value'],
          date: DateTime.fromMillisecondsSinceEpoch(m['date']),
            lesson: LessonViewModel(
              id: lessonData['id'] ?? 0,
              num: lessonData['num'] ?? 0,
              subject: lessonData['subject'] ?? '',
              topic: lessonData['topic'] ?? '',
              teacher: lessonData['teacher'] ?? '',
              teacherFull: lessonData['teacherFull'] ?? '',
              homework: lessonData['homework'] ?? '',
              homeworkFiles: [],
              startTime: lessonData['startTime'] ?? '',
              endTime: lessonData['endTime'] ?? '',
              mark: lessonData['mark'],
              markDescription: lessonData['markDescription'],
              markWeight: lessonData['markWeight'],
          ),
        );
      }).toList();

      return SubjectData(
        id: s['id'],
        name: s['name'],
        average: s['average'],
        totalMark: s['totalMark'],
        marks: marks,
        teacher: s['teacher'],
        rating: s['rating'],
      );
    }).toList();
    } catch (e) {
      print("Error loading from cache: $e");
    }
  }

  Map<int, String> _extractHomeworkFromPrsDiary(Map<String, dynamic> json) {
    Map<int, String> result = {};
    final lessons = json['lesson'] as List<dynamic>?;
    if (lessons == null) return result;

    for (var lesson in lessons) {
      final lessonId = lesson['id'] as int?;
      if (lessonId == null) continue;

      final parts = lesson['part'] as List<dynamic>?;
      if (parts == null) continue;

      for (var part in parts) {
        if (part['cat'] == 'DZ') {
          final variants = part['variant'] as List<dynamic>?;
          if (variants != null) {
            for (var v in variants) {
              final text = v['text'] as String?;
              if (text != null && text.isNotEmpty) {
                final clean = text.replaceAll(RegExp(r'<[^>]*>'), '').trim();
                if (clean.isNotEmpty) {
                  result[lessonId] = clean;
                  break;
                }
              }
            }
          }
        }
      }
    }
    return result;
  }

  void _processMarksFromPeriod(DiaryUnitResponse unitsResp, DiaryPeriodResponse diaryResp, Map<int, String> homeworkMap) {
    Map<int, List<MarkData>> marksMap = {};

    if (diaryResp.result != null) {
      for (var lesson in diaryResp.result!) {
        final unitId = lesson.unitId;
        if (unitId == null) continue;

        final lessonDate = lesson.date ?? DateTime.now();
        final lessonNum = lesson.lesNum ?? 0;
        final times = bellScheduleProvider.getLessonTime(lessonNum);
        final startTime = times?.start ?? "";
        final endTime = times?.end ?? "";
        final lessonId = lesson.lessonId ?? 0;

        final homework = homeworkMap[lessonId] ?? "";

        if (lesson.part != null) {
          for (var part in lesson.part!) {
            if (part.mark != null) {
              for (var mark in part.mark!) {
                final val = mark.markValue;
                if (val != null && val.isNotEmpty) {
                  if (!marksMap.containsKey(unitId)) {
                    marksMap[unitId] = [];
                  }

                  final unitObj = unitsResp.result?.firstWhere(
                    (u) => u.unitId == unitId,
                    orElse: () => DiaryUnit(),
                  );
                  final unitName = unitObj?.unitName ?? "Предмет";

                  final lessonVm = LessonViewModel(
                    id: lessonId,
                    num: lessonNum,
                    subject: unitName,
                    topic: lesson.subject ?? "",
                    teacher: _shortenTeacherName(lesson.teacherFio),
                    teacherFull: lesson.teacherFio ?? "",
                    homework: homework,
                    homeworkFiles: [],
                    startTime: startTime,
                    endTime: endTime,
                    mark: val,
                    markDescription: part.lptName ?? "Оценка",
                    markWeight: part.mrkWt,
                  );

                  marksMap[unitId]!.add(MarkData(
                    value: val,
                    date: lessonDate,
                    lesson: lessonVm,
                  ));
                }
              }
            }
          }
        }
      }
    }

    if (unitsResp.result != null) {
      subjects = unitsResp.result!.map((unit) {
        final unitId = unit.unitId ?? 0;
        final marks = marksMap[unitId] ?? [];

        marks.sort((a, b) => a.date.compareTo(b.date));

        String? teacher;
        if (marks.isNotEmpty) {
          final teacherFull = marks.last.lesson.teacherFull;
          if (teacherFull.isNotEmpty) {
            teacher = teacherFull;
          }
        }

        return SubjectData(
          id: unitId.toString(),
          name: unit.unitName ?? "Предмет",
          average: unit.overMark?.toStringAsFixed(2) ?? "-",
          totalMark: _formatTotalMark(unit.totalMark),
          marks: marks,
          teacher: teacher,
          rating: unit.rating,
        );
      }).toList();
    } else {
      subjects = [];
    }
  }

  String? _formatTotalMark(double? mark) {
    if (mark == null) return null;
    if (mark % 1 == 0) return mark.toStringAsFixed(0);
    return mark.toStringAsFixed(2);
  }

  String _shortenTeacherName(String? fullName) {
    if (fullName == null || fullName.isEmpty) return "";
    final parts = fullName.split(' ');
    if (parts.length >= 3) {
      return "${parts[0]} ${parts[1][0]}.${parts[2][0]}.";
    } else if (parts.length == 2) {
      return "${parts[0]} ${parts[1][0]}.";
    }
    return fullName;
  }

  List<VirtualMark> getVirtualMarks(String subjectId) {
    return _virtualMarks[subjectId] ?? [];
  }

  bool isMarkDeleted(String markId) {
    return _deletedMarkIds.contains(markId);
  }

  void addVirtualMark(String subjectId, String value, double weight, {DateTime? date}) {
    if (!_virtualMarks.containsKey(subjectId)) {
      _virtualMarks[subjectId] = [];
    }
    _virtualMarks[subjectId]!.add(VirtualMark(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      value: value,
      weight: weight,
      date: date ?? DateTime.now(),
    ));
    notifyListeners();
  }

  void editVirtualMark(String subjectId, String markId, String newValue, double newWeight) {
    final marks = _virtualMarks[subjectId];
    if (marks != null) {
      final index = marks.indexWhere((m) => m.id == markId);
      if (index != -1) {
        marks[index] = VirtualMark(
          id: markId,
          value: newValue,
          weight: newWeight,
          date: marks[index].date,
        );
        notifyListeners();
      }
    }
  }

  void deleteVirtualMark(String subjectId, String markId) {
    final marks = _virtualMarks[subjectId];
    if (marks != null) {
      marks.removeWhere((m) => m.id == markId);
      notifyListeners();
    }
  }

  void deleteOriginalMark(String markId) {
    _deletedMarkIds.add(markId);
    notifyListeners();
  }

  void restoreOriginalMark(String markId) {
    _deletedMarkIds.remove(markId);
    notifyListeners();
  }

  void resetAllChanges(String subjectId) {
    _virtualMarks.remove(subjectId);

    final subject = subjects.firstWhere((s) => s.id == subjectId, orElse: () => subjects.first);
    for (var mark in subject.marks) {
      final markId = '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
      _deletedMarkIds.remove(markId);
    }
    notifyListeners();
  }

  bool hasChanges(String subjectId) {
    final hasVirtual = _virtualMarks[subjectId]?.isNotEmpty ?? false;
    if (hasVirtual) return true;

    final subject = subjects.firstWhere((s) => s.id == subjectId, orElse: () => subjects.first);
    for (var mark in subject.marks) {
      final markId = '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
      if (_deletedMarkIds.contains(markId)) return true;
    }
    return false;
  }

  String calculateModifiedAverage(String subjectId) {
    final subject = subjects.firstWhere((s) => s.id == subjectId, orElse: () => subjects.first);
    final virtualMarks = _virtualMarks[subjectId] ?? [];

    double weightedSum = 0;
    double totalWeight = 0;

    for (var mark in subject.marks) {
      final markId = '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
      if (_deletedMarkIds.contains(markId)) continue;

      final value = SubjectData._parseMarkValue(mark.value);
      if (value == null) continue;

      final weight = mark.lesson.markWeight ?? 1.0;
      weightedSum += value * weight;
      totalWeight += weight;
    }

    for (var mark in virtualMarks) {
      final value = SubjectData._parseMarkValue(mark.value);
      if (value == null) continue;

      weightedSum += value * mark.weight;
      totalWeight += mark.weight;
    }

    if (totalWeight == 0) return "-";
    return (weightedSum / totalWeight).toStringAsFixed(2);
  }
}

class VirtualMark {
  final String id;
  final String value;
  final double weight;
  final DateTime date;

  VirtualMark({
    required this.id,
    required this.value,
    required this.weight,
    required this.date,
  });
}

class PeriodSelectionItem {
  final PeriodResponse period;
  final int groupId;
  final String groupName;
  final int depth;

  PeriodSelectionItem({
    required this.period,
    required this.groupId,
    required this.groupName,
    required this.depth,
  });

  String get displayName {
    final prefix = "  " * depth;
    return "$prefix${period.name ?? ""}";
  }
}

class SubjectData {
  final String id;
  final String name;
  final String average;
  final String? totalMark;
  final List<MarkData> marks;
  final String? teacher;
  final String? rating;

  SubjectData({
    required this.id,
    required this.name,
    required this.average,
    this.totalMark,
    required this.marks,
    this.teacher,
    this.rating,
  });

  String get calculatedAverage {
    if (marks.isEmpty) return "-";

    double weightedSum = 0;
    double totalWeight = 0;

    for (var mark in marks) {
      final value = _parseMarkValue(mark.value);
      if (value == null) continue;

      final weight = mark.lesson.markWeight ?? 1.0;
      weightedSum += value * weight;
      totalWeight += weight;
    }

    if (totalWeight == 0) return "-";
    return (weightedSum / totalWeight).toStringAsFixed(2);
  }

  static double? _parseMarkValue(String markStr) {
    if (markStr.isEmpty) return null;

    String cleaned = markStr.trim();

    if (cleaned == '!' || cleaned == 'н' || cleaned == 'б' || cleaned == 'о') {
      return null;
    }

    double modifier = 0;
    if (cleaned.endsWith('+')) {
      modifier = 0.2;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    } else if (cleaned.endsWith('-')) {
      modifier = -0.2;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    final baseValue = double.tryParse(cleaned);
    if (baseValue == null) return null;

    return baseValue + modifier;
  }
}

class MarkData {
  final String value;
  final DateTime date;
  final LessonViewModel lesson;

  MarkData({required this.value, required this.date, required this.lesson});
}