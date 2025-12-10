import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/marks_models.dart';
import '../models/lesson_view_model.dart';
import '../services/api_service.dart';
import '../providers/bell_schedule_provider.dart';

class MarksViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();
  final BellScheduleProvider bellScheduleProvider;

  List<PeriodSelectionItem> allPeriods = [];
  PeriodSelectionItem? selectedPeriod;
  List<SubjectData> subjects = [];
  
  bool isLoading = false;
  String? error;

  static const String _savedPeriodKey = "lastSelectedPeriodId";

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

  Future<void> loadMarksData() async {
    if (selectedPeriod == null || selectedPeriod!.period.id == null) return;

    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final periodId = selectedPeriod!.period.id!;
      final d1 = selectedPeriod!.period.date1 ?? 0;
      final d2 = selectedPeriod!.period.date2 ?? 0;

      final unitsJson = await _api.getDiaryUnits(periodId);
      final unitsResponse = DiaryUnitResponse.fromJson(unitsJson);

      final diaryJson = await _api.getDiaryPeriod(periodId);
      final diaryResponse = DiaryPeriodResponse.fromJson(diaryJson);

      final prsDiaryJson = await _api.getPrsDiary(d1, d2);
      final homeworkMap = _extractHomeworkFromPrsDiary(prsDiaryJson);

      _processMarksFromPeriod(unitsResponse, diaryResponse, homeworkMap);

    } catch (e) {
      error = e.toString();
      print("Error loading marks data: $e");
    } finally {
      isLoading = false;
      notifyListeners();
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

        return SubjectData(
          id: unitId.toString(),
          name: unit.unitName ?? "Предмет",
          average: unit.overMark?.toStringAsFixed(2) ?? "-",
          marks: marks,
          teacher: null,
          rating: unit.rating,
        );
      }).toList();
    } else {
      subjects = [];
    }
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
  final List<MarkData> marks;
  final String? teacher;
  final String? rating;

  SubjectData({
    required this.id,
    required this.name,
    required this.average,
    required this.marks,
    this.teacher,
    this.rating,
  });
}

class MarkData {
  final String value;
  final DateTime date;
  final LessonViewModel lesson;

  MarkData({required this.value, required this.date, required this.lesson});
}
