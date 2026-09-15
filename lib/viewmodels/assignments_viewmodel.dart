import 'package:flutter/material.dart';

import '../services/api_service.dart';
import '../utils/html_content.dart';
import '../models/diary_models.dart';
import '../models/homework_models.dart';
import '../models/lesson_view_model.dart';
import '../providers/settings_provider.dart';
import '../services/widget_data_service.dart';
import '../services/marks_cache_service.dart';

class AssignmentsViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();
  final SettingsProvider _settings;

  List<HomeworkItem> _items = [];
  bool _isLoading = false;
  String? _error;
  bool _disposed = false;
  int _loadGeneration = 0;
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  List<HomeworkItem> get items => _items;
  bool get isLoading => _isLoading;
  String? get error => _error;
  DateTime get startDate => _startDate;
  DateTime get endDate => _endDate;

  AssignmentsViewModel(this._settings) {
    _updateDatesFromSettings();
    _settings.addListener(_onSettingsChanged);
    MarksCacheService().addListener(_clearIdentityState);
  }

  void _clearIdentityState() {
    _loadGeneration++;
    _items = [];
    _isLoading = false;
    _error = null;
    if (!_disposed) notifyListeners();
  }

  void _onSettingsChanged() {
    _updateDatesFromSettings();
    loadAssignments();
  }

  void _updateDatesFromSettings() {
    final now = DateTime.now();
    _startDate = DateTime(now.year, now.month, now.day - _settings.hwDaysPast);
    _endDate = DateTime(
      now.year,
      now.month,
      now.day + _settings.hwDaysFuture + 1,
    ).subtract(const Duration(microseconds: 1));
  }

  void updateDateRange(DateTime start, DateTime end) {
    _startDate = DateUtils.dateOnly(start);
    _endDate = DateTime(
      end.year,
      end.month,
      end.day + 1,
    ).subtract(const Duration(microseconds: 1));
    loadAssignments();
  }

  Future<void> loadAssignments({bool forWidgets = false}) async {
    if (_disposed) return;
    final generation = ++_loadGeneration;
    final epoch = _api.identityEpoch;
    final today = DateUtils.dateOnly(DateTime.now());
    final start = forWidgets ? today : _startDate;
    final end = forWidgets
        ? DateTime(today.year, today.month, today.day + 15)
        : _endDate;
    bool current() =>
        !_disposed &&
        generation == _loadGeneration &&
        epoch == _api.identityEpoch;
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_api.currentPrsId == null) {
        throw Exception('User PrsID not found. Please log in.');
      }

      final d1 = start.millisecondsSinceEpoch.toDouble();
      final d2 = end.millisecondsSinceEpoch.toDouble();

      final data = await _api.getPrsDiary(d1, d2);
      if (!current()) return;
      final response = PrsDiaryResponse.fromJson(data);

      List<HomeworkItem> newItems = [];

      if (response.lesson != null) {
        for (var lesson in response.lesson!) {
          if (lesson.date == null || lesson.part == null) continue;

          final lessonDate = DateTime.fromMillisecondsSinceEpoch(
            lesson.date!.toInt(),
          );
          final subject = lesson.unit?.name ?? "Предмет";

          for (var part in lesson.part!) {
            if (part.cat == "DZ") {
              if (part.variant != null) {
                for (var variant in part.variant!) {
                  final rawText = variant.text ?? "";
                  final cleanText = htmlToPlainText(rawText);

                  List<HomeworkFile> hwFiles = [];

                  // картинки из текста вытаскиваем как отдельные файлы
                  final imgRegex = RegExp(
                    r'<img\s[^>]*src="([^"]*)"',
                    caseSensitive: false,
                  );
                  int imgIndex = 1;
                  for (final match in imgRegex.allMatches(rawText)) {
                    final imgUrl = match.group(1);
                    if (imgUrl != null) {
                      final urlParts = imgUrl.split('/');
                      final fileIdStr = urlParts.isNotEmpty
                          ? urlParts.last.split('?').first
                          : '';
                      final fileId = int.tryParse(fileIdStr) ?? 0;
                      hwFiles.add(
                        HomeworkFile(
                          id: fileId,
                          name: 'Изображение $imgIndex.jpg',
                          variantId: variant.id ?? 0,
                          url: imgUrl.split('?').first,
                        ),
                      );
                      imgIndex++;
                    }
                  }

                  if (variant.file != null && variant.id != null) {
                    for (var f in variant.file!) {
                      if (f.id != null && f.fileName != null) {
                        hwFiles.add(
                          HomeworkFile(
                            id: f.id!,
                            name: f.fileName!,
                            variantId: variant.id!,
                          ),
                        );
                      }
                    }
                  }

                  if (rawText.trim().isNotEmpty || hwFiles.isNotEmpty) {
                    newItems.add(
                      HomeworkItem(
                        date: lessonDate,
                        subject: subject,
                        text: cleanText,
                        html: rawText,
                        files: hwFiles,
                        deadline: variant.deadLine,
                        partId: part.id,
                      ),
                    );
                  }
                }
              }
            }
          }
        }
      }

      // дотягиваем данные из lpart
      await _mergeLPartItems(newItems, start, end);
      if (!current()) return;

      newItems.sort((a, b) => b.date.compareTo(a.date));
      _items = newItems;

      // обновляем виджет
      if (!start.isAfter(today) && !end.isBefore(today)) {
        WidgetDataService().updateHomeworkWidget(items: _items);
      }
    } catch (e) {
      if (current()) _error = e.toString();
    } finally {
      if (current()) {
        _isLoading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _mergeLPartItems(
    List<HomeworkItem> existingItems,
    DateTime start,
    DateTime end,
  ) async {
    try {
      final yearId = await _api.getCurrentYearId();
      final begDate = start.millisecondsSinceEpoch;
      final endDate = end.millisecondsSinceEpoch;

      final lpartItems = await _api.getLPartListPupil(begDate, endDate, yearId);

      // превью может обрываться посреди слова, сравниваем сначала части урока
      final existingPartIds = existingItems
          .map((item) => item.partId)
          .whereType<int>()
          .toSet();
      String contentKey(DateTime date, String subject, String text) =>
          '${date.year}-${date.month}-${date.day}|${subject.trim().toLowerCase()}|${htmlToPlainText(text).replaceAll(RegExp(r'\s+'), ' ').trim().toLowerCase()}';
      final existingKeys = <String>{};
      for (final item in existingItems) {
        if (item.text.trim().isNotEmpty) {
          existingKeys.add(contentKey(item.date, item.subject, item.text));
        }
      }

      for (final lpart in lpartItems) {
        if (lpart.passDt == null) continue;
        if (existingPartIds.contains(lpart.partId)) continue;
        final preview = lpart.preview ?? '';
        if (preview.isEmpty && (lpart.attachCnt ?? 0) == 0) continue;

        final date = DateTime.fromMillisecondsSinceEpoch(lpart.passDt!);
        final subject = lpart.unitName ?? 'Предмет';
        final dedupKey = contentKey(date, subject, preview);
        if (preview.trim().isNotEmpty && existingKeys.contains(dedupKey)) {
          continue;
        }

        // собираем имя учителя
        String? teacherName;
        if (lpart.tchArray.isNotEmpty) {
          teacherName = lpart.tchArray.first.fullName;
        }

        existingItems.add(
          HomeworkItem(
            date: date,
            subject: subject,
            text: preview,
            files: [],
            attachCount: lpart.attachCnt,
            partId: lpart.partId,
            catName: lpart.catName,
            teacherName: teacherName,
          ),
        );
        if (preview.trim().isNotEmpty) existingKeys.add(dedupKey);
        if (lpart.partId != null) existingPartIds.add(lpart.partId!);
      }
    } catch (e) {
      // lpart не ответил, переживём, данные дневника на месте
      debugPrint("LPart merge failed: $e");
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _loadGeneration++;
    MarksCacheService().removeListener(_clearIdentityState);
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}
