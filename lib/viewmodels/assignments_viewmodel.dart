import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../models/diary_models.dart';
import '../models/homework_models.dart';
import '../models/lesson_view_model.dart';
import '../providers/settings_provider.dart';
import '../services/widget_data_service.dart';

class AssignmentsViewModel extends ChangeNotifier {
  final ApiService _api = ApiService();
  final SettingsProvider _settings;

  List<HomeworkItem> _items = [];
  bool _isLoading = false;
  String? _error;
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
  }

  void _onSettingsChanged() {
    _updateDatesFromSettings();
    loadAssignments();
  }

  void _updateDatesFromSettings() {
    final now = DateTime.now();
    _startDate = now.subtract(Duration(days: _settings.hwDaysPast));
    _endDate = now.add(Duration(days: _settings.hwDaysFuture));
  }

  void updateDateRange(DateTime start, DateTime end) {
    _startDate = start;
    _endDate = end;
    loadAssignments();
  }

  Future<void> loadAssignments() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      if (_api.currentPrsId == null) {
        throw Exception('User PrsID not found. Please log in.');
      }

      final d1 = _startDate.millisecondsSinceEpoch.toDouble();
      final d2 = _endDate.millisecondsSinceEpoch.toDouble();

      final data = await _api.getPrsDiary(d1, d2);
      final response = PrsDiaryResponse.fromJson(data);

      List<HomeworkItem> newItems = [];

      if (response.lesson != null) {
        for (var lesson in response.lesson!) {
          if (lesson.date == null || lesson.part == null) continue;

          final lessonDate = DateTime.fromMillisecondsSinceEpoch(lesson.date!.toInt());
          final subject = lesson.unit?.name ?? "Предмет";

          for (var part in lesson.part!) {
            if (part.cat == "DZ") {
              if (part.variant != null) {
                for (var variant in part.variant!) {
                  final rawText = variant.text ?? "";
                  final cleanText = _stripHtml(rawText);

                  List<HomeworkFile> hwFiles = [];
                  if (variant.file != null && variant.id != null) {
                    for (var f in variant.file!) {
                      if (f.id != null && f.fileName != null) {
                        hwFiles.add(HomeworkFile(
                          id: f.id!,
                          name: f.fileName!,
                          variantId: variant.id!
                        ));
                      }
                    }
                  }

                  if (cleanText.isNotEmpty || hwFiles.isNotEmpty) {
                    newItems.add(HomeworkItem(
                      date: lessonDate,
                      subject: subject,
                      text: cleanText,
                      files: hwFiles,
                      deadline: variant.deadLine,
                    ));
                  }
                }
              }
            }
          }
        }
      }

      newItems.sort((a, b) => b.date.compareTo(a.date));
      _items = newItems;

      WidgetDataService().updateHomeworkWidget(items: _items);

    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  String _stripHtml(String htmlString) {
    final RegExp exp = RegExp(r"<[^>]*>", multiLine: true, caseSensitive: true);

    String intermediate = htmlString
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</div>', caseSensitive: false), '\n');

    return intermediate.replaceAll(exp, '').trim();
  }

  @override
  void dispose() {
    _settings.removeListener(_onSettingsChanged);
    super.dispose();
  }
}