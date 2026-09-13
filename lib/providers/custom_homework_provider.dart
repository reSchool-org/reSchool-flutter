import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/custom_homework.dart';
import '../services/custom_homework_service.dart';

class CustomHomeworkProvider extends ChangeNotifier {
  final CustomHomeworkService _service = CustomHomeworkService();

  final Map<String, List<CustomHomework>> _homeworkByDateAndSubject = {};
  bool _isLoading = false;
  String? _error;
  DateTime? _loadedWeekStart;

  bool get isLoading => _isLoading;
  String? get error => _error;

  List<CustomHomework> getHomeworkForSubjectAndDate(String subject, DateTime date) {
    final key = _makeKey(date, subject);
    return _homeworkByDateAndSubject[key] ?? [];
  }

  List<CustomHomework> getHomeworkForDate(DateTime date) {
    final dateStr = _formatDate(date);
    final result = <CustomHomework>[];
    for (final entry in _homeworkByDateAndSubject.entries) {
      if (entry.key.startsWith(dateStr)) {
        result.addAll(entry.value);
      }
    }
    return result;
  }

  Future<void> loadHomeworkForWeek(DateTime weekStart) async {
    // ту же неделю второй раз не грузим
    if (_loadedWeekStart != null &&
        _loadedWeekStart!.year == weekStart.year &&
        _loadedWeekStart!.month == weekStart.month &&
        _loadedWeekStart!.day == weekStart.day) {
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final weekEnd = weekStart.add(const Duration(days: 6));
      final homework = await _service.getHomework(dateFrom: weekStart, dateTo: weekEnd);

      _homeworkByDateAndSubject.clear();
      for (final hw in homework) {
        final key = _makeKey(hw.lessonDate, hw.subject);
        _homeworkByDateAndSubject.putIfAbsent(key, () => []).add(hw);
      }

      _loadedWeekStart = weekStart;
      _error = null;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error loading custom homework: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshCurrentWeek() async {
    if (_loadedWeekStart != null) {
      final weekStart = _loadedWeekStart;
      _loadedWeekStart = null;
      await loadHomeworkForWeek(weekStart!);
    }
  }

  Future<CustomHomework?> createHomework({
    required String subject,
    required DateTime lessonDate,
    required String text,
    List<File>? files,
  }) async {
    _error = null;
    try {
      final homework = await _service.createHomework(
        subject: subject,
        lessonDate: lessonDate,
        text: text,
        files: files,
      );

      final key = _makeKey(lessonDate, subject);
      _homeworkByDateAndSubject.putIfAbsent(key, () => []).insert(0, homework);
      notifyListeners();

      return homework;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error creating homework: $e');
      rethrow;
    }
  }

  Future<CustomHomework?> updateHomework({
    required int homeworkId,
    required String subject,
    required DateTime lessonDate,
    String? text,
    List<int>? deleteFileIds,
    List<File>? newFiles,
  }) async {
    _error = null;
    try {
      final homework = await _service.updateHomework(
        homeworkId: homeworkId,
        text: text,
        deleteFileIds: deleteFileIds,
        newFiles: newFiles,
      );

      final key = _makeKey(lessonDate, subject);
      final list = _homeworkByDateAndSubject[key];
      if (list != null) {
        final index = list.indexWhere((h) => h.id == homeworkId);
        if (index != -1) list[index] = homework;
      }
      notifyListeners();

      return homework;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error updating homework: $e');
      rethrow;
    }
  }

  Future<bool> deleteHomework({
    required int homeworkId,
    required String subject,
    required DateTime lessonDate,
  }) async {
    _error = null;
    try {
      await _service.deleteHomework(homeworkId: homeworkId);

      final key = _makeKey(lessonDate, subject);
      _homeworkByDateAndSubject[key]?.removeWhere((h) => h.id == homeworkId);
      notifyListeners();

      return true;
    } catch (e) {
      _error = e.toString();
      debugPrint('Error deleting homework: $e');
      return false;
    }
  }

  Future<File?> downloadFile({
    required int fileId,
    required String fileName,
  }) async {
    try {
      return await _service.downloadFile(fileId: fileId, fileName: fileName);
    } catch (e) {
      debugPrint('Error downloading file: $e');
      return null;
    }
  }

  void clearCache() {
    _homeworkByDateAndSubject.clear();
    _loadedWeekStart = null;
    notifyListeners();
  }

  String _makeKey(DateTime date, String subject) => '${_formatDate(date)}_$subject';

  String _formatDate(DateTime date) {
    return '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
  }
}
