import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/marks_models.dart';
import '../models/diary_models.dart';
import '../services/school_cache_policy.dart';
import '../models/lesson_view_model.dart';
import '../models/plan_success_models.dart';
import '../models/pupil_units_models.dart';
import '../models/widget_models.dart';
import '../services/api_service.dart';
import '../services/marks_cache_service.dart';
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

  // аналитика по выполнению плана
  List<PupilUnit> analyticsUnits = [];
  bool analyticsUnitsLoading = false;
  String? analyticsUnitsError;

  final Map<String, PlanSuccessRoot> _planSuccessByKey = {};
  final Set<String> _planSuccessLoadingKeys = {};
  final Map<String, String> _planSuccessErrorByKey = {};

  // виртуальные оценки, никуда не сохраняются, ключ это id предмета
  final Map<String, List<VirtualMark>> _virtualMarks = {};
  final Set<String> _deletedMarkIds =
      {}; // id настоящих оценок, которые пользователь скрыл

  static const String _savedPeriodKey = "lastSelectedPeriodId";
  static const String _cachePrefix = "marks_cache_";
  static const String _cacheTimePrefix = "marks_cache_time_";
  static const Duration _cacheExpiry = SchoolCachePolicy.lifetime;

  final MarksCacheService _marksCache = MarksCacheService();
  bool _disposed = false;
  _MarksLoad? _activeMarksLoad;

  MarksViewModel(this.bellScheduleProvider) {
    _marksCache.addListener(_clearIdentityState);
  }

  bool _isCurrent(int generation) =>
      !_disposed && generation == _marksCache.generation;

  String? get _cacheIdentity {
    final userId = _api.studentUserId;
    final prsId = _api.studentPrsId;
    if (userId == null || prsId == null) return null;
    return '${_api.isDemo ? 'demo' : 'school'}_${userId}_$prsId';
  }

  void _clearIdentityState() {
    _activeMarksLoad = null;
    allPeriods = [];
    selectedPeriod = null;
    subjects = [];
    analyticsUnits = [];
    _planSuccessByKey.clear();
    _planSuccessLoadingKeys.clear();
    _planSuccessErrorByKey.clear();
    _virtualMarks.clear();
    _deletedMarkIds.clear();
    isLoading = false;
    isRefreshing = false;
    analyticsUnitsLoading = false;
    error = null;
    analyticsUnitsError = null;
    lastUpdated = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _activeMarksLoad = null;
    _marksCache.removeListener(_clearIdentityState);
    super.dispose();
  }

  int? get currentUserId => _api.studentUserId;

  Future<void> loadPeriods({bool forceRefresh = false}) async {
    final generation = _marksCache.generation;
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final groupsJson = await _api.getClassByUser();
      if (!_isCurrent(generation)) return;
      final groups = groupsJson.map((e) => GroupResponse.fromJson(e)).toList();

      groups.sort((a, b) => (b.begDate ?? 0).compareTo(a.begDate ?? 0));

      final filterPrefs = await SharedPreferences.getInstance();
      if (!_isCurrent(generation)) return;
      if (filterPrefs.getBool('display_only_current_class') ?? true) {
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
        if (!_isCurrent(generation)) return;
        final rootPeriod = PeriodResponse.fromJson(periodsJson);

        if (rootPeriod.items != null) {
          final flat = _flattenPeriods(
            rootPeriod.items!,
            0,
            academicYear: rootPeriod.typeCode == 'Y' ? rootPeriod : null,
          );
          items.addAll(
            flat.map(
              (p) => PeriodSelectionItem(
                period: p.period,
                groupId: group.groupId!,
                groupName: group.groupName ?? "Group ${group.groupId}",
                depth: p.depth,
                academicYear: p.academicYear,
                groupStartDate: group.begDate,
              ),
            ),
          );
        }
      }

      allPeriods = items;

      final prefs = await SharedPreferences.getInstance();
      if (!_isCurrent(generation)) return;
      final savedId = prefs.getInt(_savedPeriodKey);

      if (savedId != null && savedId != 0) {
        try {
          selectedPeriod = allPeriods.firstWhere((p) => p.period.id == savedId);
        } catch (_) {}
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
        await _loadMarks(forceRefresh: forceRefresh);
      }
    } catch (e) {
      if (!_isCurrent(generation)) return;
      error = e.toString();
      debugPrint("Error loading periods: $e");
    } finally {
      if (_isCurrent(generation) && _activeMarksLoad == null) {
        isLoading = false;
        notifyListeners();
      }
    }
  }

  List<({PeriodResponse period, int depth, PeriodResponse? academicYear})>
  _flattenPeriods(
    List<PeriodResponse> periods,
    int depth, {
    PeriodResponse? academicYear,
  }) {
    final result =
        <({PeriodResponse period, int depth, PeriodResponse? academicYear})>[];

    periods.sort((a, b) => (a.date1 ?? 0).compareTo(b.date1 ?? 0));

    for (var p in periods) {
      final code = p.typeCode ?? "";
      final year = code == 'Y' ? p : academicYear;

      final isValid = code == "Q" || code == "HY" || code == "Y";

      if (isValid) {
        result.add((period: p, depth: depth, academicYear: year));
      }

      if (p.items != null) {
        final nextDepth = isValid ? depth + 1 : depth;
        result.addAll(_flattenPeriods(p.items!, nextDepth, academicYear: year));
      }
    }
    return result;
  }

  void selectPeriod(PeriodSelectionItem item) {
    selectedPeriod = item;
    if (item.period.id != null) {
      final generation = _marksCache.generation;
      _marksCache.writeIfCurrent(generation, () async {
        final prefs = await SharedPreferences.getInstance();
        if (_isCurrent(generation)) {
          await prefs.setInt(_savedPeriodKey, item.period.id!);
        }
      });
    }
    loadMarksData();
  }

  Future<void> loadAnalyticsUnits({bool forceRefresh = false}) async {
    final generation = _marksCache.generation;
    if (analyticsUnitsLoading) return;
    if (!forceRefresh && analyticsUnits.isNotEmpty) return;

    analyticsUnitsLoading = true;
    analyticsUnitsError = null;
    notifyListeners();

    try {
      final yearId = await _api.getCurrentYearId();
      if (!_isCurrent(generation)) return;
      final prsId = _api.studentPrsId;
      if (prsId == null) throw Exception('PRS ID not found');

      final json = await _api.getPupilUnits(
        prsId,
        yearId,
        forceRefresh: forceRefresh,
      );
      if (!_isCurrent(generation)) return;
      final parsed = PupilUnitsResponse.fromJson(json);

      analyticsUnits =
          parsed.result
              .where((u) => u.unitId != 0 && u.name.isNotEmpty)
              .toList()
            ..sort((a, b) => a.name.compareTo(b.name));
    } catch (e) {
      if (!_isCurrent(generation)) return;
      analyticsUnitsError = e.toString();
      analyticsUnits = [];
    } finally {
      if (_isCurrent(generation)) {
        analyticsUnitsLoading = false;
        notifyListeners();
      }
    }
  }

  String _planKey(int groupId, int unitId, int userId) =>
      '$groupId:$unitId:$userId';

  PlanSuccessRoot? getPlanSuccessForUnit(int unitId) {
    final period = selectedPeriod;
    final userId = _api.studentUserId;
    if (period == null || userId == null) return null;
    return _planSuccessByKey[_planKey(period.groupId, unitId, userId)];
  }

  bool isPlanSuccessLoading(int unitId) {
    final period = selectedPeriod;
    final userId = _api.studentUserId;
    if (period == null || userId == null) return false;
    return _planSuccessLoadingKeys.contains(
      _planKey(period.groupId, unitId, userId),
    );
  }

  String? getPlanSuccessError(int unitId) {
    final period = selectedPeriod;
    final userId = _api.studentUserId;
    if (period == null || userId == null) return null;
    return _planSuccessErrorByKey[_planKey(period.groupId, unitId, userId)];
  }

  Future<void> loadPlanSuccessForUnit(
    int unitId, {
    bool forceRefresh = false,
  }) async {
    final generation = _marksCache.generation;
    final period = selectedPeriod;
    if (period == null) return;

    if (_api.studentUserId == null) {
      await _api.getClassByUser();
    }
    if (!_isCurrent(generation)) return;
    final userId = _api.studentUserId;
    if (userId == null) return;

    final key = _planKey(period.groupId, unitId, userId);
    if (_planSuccessLoadingKeys.contains(key)) return;

    _planSuccessLoadingKeys.add(key);
    _planSuccessErrorByKey.remove(key);
    notifyListeners();

    try {
      final json = await _api.getPlanSuccess(
        groupId: period.groupId,
        unitId: unitId,
        userId: userId,
        forceRefresh: forceRefresh,
      );

      if (!_isCurrent(generation)) return;
      final parsed = PlanSuccessResponse.fromJson(json).root;
      if (parsed == null) throw Exception('Empty analytics response');

      _planSuccessByKey[key] = parsed;
    } catch (e) {
      if (!_isCurrent(generation)) return;
      _planSuccessErrorByKey[key] = e.toString();
    } finally {
      if (_isCurrent(generation)) {
        _planSuccessLoadingKeys.remove(key);
        notifyListeners();
      }
    }
  }

  Future<void> refreshMarksData() => _loadMarks(forceRefresh: true);

  Future<void> loadMarksData() => _loadMarks(forceRefresh: false);

  Future<void> _loadMarks({required bool forceRefresh}) {
    final period = selectedPeriod;
    if (_disposed || period == null || period.period.id == null) {
      return Future.value();
    }
    final generation = _marksCache.generation;
    final identity = _cacheIdentity;
    final active = _activeMarksLoad;
    if (active != null &&
        active.generation == generation &&
        active.identity == identity &&
        identical(active.period, period) &&
        (!forceRefresh || active.forceRefresh)) {
      return active.completion.future;
    }

    // обновление отменяет загрузку из кеша; повторы объединяем только для того же периода и аккаунта
    final load = _MarksLoad(period, generation, identity, forceRefresh);
    _activeMarksLoad = load;
    isLoading = !forceRefresh || subjects.isEmpty;
    isRefreshing = forceRefresh;
    error = null;
    notifyListeners();
    unawaited(_runMarksLoad(load));
    return load.completion.future;
  }

  bool _ownsMarksLoad(_MarksLoad load) =>
      _isCurrent(load.generation) &&
      identical(_activeMarksLoad, load) &&
      identical(selectedPeriod, load.period) &&
      (load.identity == null || load.identity == _cacheIdentity);

  Future<void> _runMarksLoad(_MarksLoad load) async {
    try {
      if (_ownsMarksLoad(load)) await _fetchAndCacheMarksData(load);
    } finally {
      if (_ownsMarksLoad(load)) {
        _activeMarksLoad = null;
        isLoading = false;
        isRefreshing = false;
        notifyListeners();
      }
      load.completion.complete();
    }
  }

  Future<void> _fetchAndCacheMarksData(_MarksLoad load) async {
    final generation = load.generation;
    final period = load.period;
    final periodId = period.period.id!;
    bool current() => _ownsMarksLoad(load);

    try {
      // определяем владельца до чтения оценок, старые ключи без владельца переносить нельзя
      if (_cacheIdentity == null) await _api.getClassByUser();
      if (!current()) return;
      final identity = _cacheIdentity;
      if (identity == null) throw StateError('Marks identity unavailable');
      bool owned() => current() && identity == _cacheIdentity;
      final cacheKey =
          '$_cachePrefix${SchoolCachePolicy.namespace}_${identity}_$periodId';
      final cacheTimeKey =
          '$_cacheTimePrefix${SchoolCachePolicy.namespace}_${identity}_$periodId';
      final prefs = await SharedPreferences.getInstance();
      if (!owned()) return;

      Future<void> publishWidget() async {
        if (!owned()) return;
        await WidgetDataService().updateGradesWidget(
          grades: subjects
              .map(
                (s) => WidgetGrade(
                  subject: s.name,
                  average: s.average,
                  rating: s.rating,
                  totalMarks: s.marks.length,
                ),
              )
              .toList(),
          periodName: period.period.name ?? "Период",
        );
      }

      if (!load.forceRefresh) {
        final cachedData = prefs.getString(cacheKey);
        final cachedTimeMs = prefs.getInt(cacheTimeKey);
        if (cachedData != null && cachedTimeMs != null) {
          final cachedTime = DateTime.fromMillisecondsSinceEpoch(cachedTimeMs);
          final age = DateTime.now().difference(cachedTime);
          if (!age.isNegative &&
              age < _cacheExpiry &&
              _loadFromCache(cachedData)) {
            lastUpdated = cachedTime;
            await _marksCache.writeIfCurrent(generation, publishWidget);
            return;
          }
        }
      }

      // публикуем результат после успеха всех трёх запросов; Future.wait соберёт и одновременные ошибки
      final responses = await Future.wait([
        _api.getDiaryUnits(periodId),
        _api.getDiaryPeriod(periodId),
        _api.getPrsDiary(period.period.date1 ?? 0, period.period.date2 ?? 0),
      ]);
      if (!owned()) return;
      final unitsResponse = DiaryUnitResponse.fromJson(responses[0]);
      final diaryResponse = DiaryPeriodResponse.fromJson(responses[1]);
      final prsDiaryJson = responses[2];
      final homeworkMap = _extractHomeworkFromPrsDiary(prsDiaryJson);
      final diaryLessons = PrsDiaryResponse.fromJson(prsDiaryJson).lesson ?? [];
      _processMarksFromPeriod(unitsResponse, diaryResponse, homeworkMap, {
        for (final lesson in diaryLessons)
          if (lesson.id != null) lesson.id!: lesson,
      });
      final cacheData = _serializeSubjects();
      final updated = DateTime.now();
      lastUpdated = updated;
      await _marksCache.writeIfCurrent(generation, () async {
        if (!owned()) return;
        await prefs.setString(cacheKey, cacheData);
        await prefs.setInt(cacheTimeKey, updated.millisecondsSinceEpoch);
        await publishWidget();
      });
    } catch (e) {
      if (!current()) return;
      error = e.toString();
      debugPrint("Error loading marks data: $e");
    }
  }

  String _serializeSubjects() {
    final list = subjects
        .map(
          (s) => {
            'id': s.id,
            'name': s.name,
            'average': s.average,
            'totalMark': s.totalMark,
            'teacher': s.teacher,
            'rating': s.rating,
            'marks': s.marks
                .map(
                  (m) => {
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
                  },
                )
                .toList(),
          },
        )
        .toList();
    return jsonEncode(list);
  }

  bool _loadFromCache(String cacheData) {
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
      return true;
    } catch (e) {
      debugPrint("Error loading from cache: $e");
      return false;
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
                final clean = text
                    .replaceAll(
                      RegExp(r'<br\s*/?>', caseSensitive: false),
                      '\n',
                    )
                    .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
                    .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n')
                    .replaceAll(RegExp(r'<[^>]*>'), '')
                    .replaceAll(RegExp(r'\n{3,}'), '\n\n')
                    .trim();
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

  void _processMarksFromPeriod(
    DiaryUnitResponse unitsResp,
    DiaryPeriodResponse diaryResp,
    Map<int, String> homeworkMap,
    Map<int, PrsDiaryLesson> diaryLessons,
  ) {
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
        final diaryLesson = diaryLessons[lessonId];
        final hasDiaryTeacher = diaryLesson?.hasTeacherAssignment ?? false;

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
                    teacher: hasDiaryTeacher
                        ? diaryLesson!.teacherShortName
                        : _shortenTeacherName(lesson.teacherFio),
                    teacherFull: hasDiaryTeacher
                        ? diaryLesson!.teacherFullName
                        : lesson.teacherFio ?? '',
                    homework: homework,
                    homeworkFiles: [],
                    startTime: startTime,
                    endTime: endTime,
                    mark: val,
                    markDescription: part.lptName ?? "Оценка",
                    markWeight: part.mrkWt,
                  );

                  marksMap[unitId]!.add(
                    MarkData(value: val, date: lessonDate, lesson: lessonVm),
                  );
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

        // учителя вытаскиваем из самой свежей оценки, если она есть
        String? teacher;
        if (marks.isNotEmpty) {
          final teacherFull = marks.last.lesson.teacherFull;
          if (teacherFull.isNotEmpty) {
            teacher = teacherFull;
          }
        }

        // заголовки предметов нужны и до первой оценки
        final assignedLessons =
            diaryLessons.values
                .where(
                  (lesson) =>
                      lesson.unit?.id == unitId && lesson.hasTeacherAssignment,
                )
                .toList()
              ..sort((a, b) => (a.date ?? 0).compareTo(b.date ?? 0));
        if (assignedLessons.isNotEmpty) {
          final name = assignedLessons.last.teacherFullName;
          teacher = name.isEmpty ? null : name;
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

  String _shortenTeacherName(String? fullName) =>
      PrsDiaryTeacher(factTeacherIN: fullName).shortName;

  // всё про виртуальные оценки
  List<VirtualMark> getVirtualMarks(String subjectId) {
    return _virtualMarks[subjectId] ?? [];
  }

  bool isMarkDeleted(String markId) {
    return _deletedMarkIds.contains(markId);
  }

  void addVirtualMark(
    String subjectId,
    String value,
    double weight, {
    DateTime? date,
  }) {
    if (!_virtualMarks.containsKey(subjectId)) {
      _virtualMarks[subjectId] = [];
    }
    _virtualMarks[subjectId]!.add(
      VirtualMark(
        id: DateTime.now().millisecondsSinceEpoch.toString(),
        value: value,
        weight: weight,
        date: date ?? DateTime.now(),
      ),
    );
    notifyListeners();
  }

  void editVirtualMark(
    String subjectId,
    String markId,
    String newValue,
    double newWeight,
  ) {
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
    // убираем скрытые оценки этого предмета
    final subject = subjects.firstWhere(
      (s) => s.id == subjectId,
      orElse: () => subjects.first,
    );
    for (var mark in subject.marks) {
      final markId =
          '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
      _deletedMarkIds.remove(markId);
    }
    notifyListeners();
  }

  bool hasChanges(String subjectId) {
    final hasVirtual = _virtualMarks[subjectId]?.isNotEmpty ?? false;
    if (hasVirtual) return true;

    final subject = subjects.firstWhere(
      (s) => s.id == subjectId,
      orElse: () => subjects.first,
    );
    for (var mark in subject.marks) {
      final markId =
          '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
      if (_deletedMarkIds.contains(markId)) return true;
    }
    return false;
  }

  /// средний балл с учётом виртуальных оценок и без скрытых
  String calculateModifiedAverage(String subjectId) {
    final subject = subjects.firstWhere(
      (s) => s.id == subjectId,
      orElse: () => subjects.first,
    );
    final virtualMarks = _virtualMarks[subjectId] ?? [];

    double weightedSum = 0;
    double totalWeight = 0;

    // сначала настоящие, кроме скрытых
    for (var mark in subject.marks) {
      final markId =
          '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
      if (_deletedMarkIds.contains(markId)) continue;

      final value = SubjectData._parseMarkValue(mark.value);
      if (value == null) continue;

      final weight = mark.lesson.markWeight ?? 1.0;
      weightedSum += value * weight;
      totalWeight += weight;
    }

    // потом виртуальные
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
  final PeriodResponse? academicYear;
  final double? groupStartDate;

  PeriodSelectionItem({
    required this.period,
    required this.groupId,
    required this.groupName,
    required this.depth,
    this.academicYear,
    this.groupStartDate,
  });

  String get contextLabel {
    final year = academicYear ?? (period.typeCode == 'Y' ? period : null);
    final startTimestamp = year?.date1 ?? groupStartDate ?? period.date1;
    if (startTimestamp == null) return groupName;

    final start = DateTime.fromMillisecondsSinceEpoch(startTimestamp.toInt());
    final startYear = year?.date1 != null
        ? start.year
        : (start.month >= 9 ? start.year : start.year - 1);
    final endYear = year?.date2 != null
        ? DateTime.fromMillisecondsSinceEpoch(year!.date2!.toInt()).year
        : startYear + 1;
    final yearLabel = startYear == endYear
        ? '$startYear'
        : '$startYear-$endYear';
    return [yearLabel, groupName].where((part) => part.isNotEmpty).join(' · ');
  }

  String get displayName {
    final prefix = "  " * depth;
    return "$prefix${period.name ?? ""}";
  }
}

class SubjectData {
  final String id;
  final String name;
  final String average; // средний балл, как его отдаёт api
  final String? totalMark; // итоговая за четверть
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

  /// взвешенный средний балл, посчитанный нами
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

  /// разбирает значение оценки вместе с плюсами и минусами
  /// 5 это 5.0, 4+ это 4.2, пятёрка с минусом 4.8, восклицательный знак это null
  static double? _parseMarkValue(String markStr) {
    if (markStr.isEmpty) return null;

    // выкидываем пробелы
    String cleaned = markStr.trim();

    // если это чистая пометка (!, н, б и прочее), нам нечего считать
    if (cleaned == '!' || cleaned == 'н' || cleaned == 'б' || cleaned == 'о') {
      return null;
    }

    // смотрим, нет ли в конце плюса или минуса
    double modifier = 0;
    if (cleaned.endsWith('+')) {
      modifier = 0.2;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    } else if (cleaned.endsWith('-')) {
      modifier = -0.2;
      cleaned = cleaned.substring(0, cleaned.length - 1);
    }

    // а теперь само число
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

/// одна загрузка оценок объединяет всех, кто ждёт её результат
class _MarksLoad {
  final PeriodSelectionItem period;
  final int generation;
  final String? identity;
  final bool forceRefresh;
  final completion = Completer<void>();

  _MarksLoad(this.period, this.generation, this.identity, this.forceRefresh);
}
