import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:home_widget/home_widget.dart';
import 'package:intl/intl.dart';
import '../models/widget_models.dart';
import '../models/lesson_view_model.dart';
import '../models/homework_models.dart';
import '../models/marks_models.dart';

class WidgetDataService {
  static final WidgetDataService _instance = WidgetDataService._internal();
  factory WidgetDataService() => _instance;
  WidgetDataService._internal();

  static const String _iOSWidgetName = 'ReSchoolWidgets';
  static const String _androidScheduleWidget = 'ScheduleWidget';
  static const String _androidHomeworkWidget = 'HomeworkWidget';
  static const String _androidGradesWidget = 'GradesWidget';

  static const MethodChannel _macOSChannel =
      MethodChannel('com.magisky.reschoolbeta/widgets');

  Future<void> initialize() async {
    if (kIsWeb) return;

    try {
      if (Platform.isIOS) {
        await HomeWidget.setAppGroupId(WidgetDataKeys.appGroup);
      }
    } catch (e) {
      debugPrint('Widget initialization error: $e');
    }
  }

  Future<void> _saveMacOSWidgetData(String key, String data) async {
    try {
      debugPrint('[WidgetDataService] Saving macOS widget data for key: $key, length: ${data.length}');
      await _macOSChannel.invokeMethod('saveWidgetData', {
        'key': key,
        'data': data,
      });
      debugPrint('[WidgetDataService] Successfully saved data for key: $key');
    } catch (e) {
      debugPrint('[WidgetDataService] Error saving macOS widget data: $e');
    }
  }

  Future<void> _reloadMacOSWidgets() async {
    try {
      await _macOSChannel.invokeMethod('reloadWidgets');
    } catch (e) {
      debugPrint('Error reloading macOS widgets: $e');
    }
  }

  Future<void> _reloadMacOSWidget(String kind) async {
    try {
      await _macOSChannel.invokeMethod('reloadWidget', {'kind': kind});
    } catch (e) {
      debugPrint('Error reloading macOS widget: $e');
    }
  }

  Future<void> updateScheduleWidget({
    required List<LessonViewModel> lessons,
    required DateTime date,
  }) async {
    if (kIsWeb) return;

    try {
      final dateStr = DateFormat('d MMMM', 'ru').format(date);

      final widgetLessons = lessons
          .where((l) => !l.isPlaceholder)
          .map((l) => WidgetLesson(
            num: l.num,
            subject: l.subject,
            teacher: l.teacher,
            startTime: l.startTime,
            endTime: l.endTime,
            mark: l.mark,
            isPlaceholder: l.isPlaceholder,
          ))
          .toList();

      final data = WidgetScheduleData(
        date: dateStr,
        lessons: widgetLessons,
        lastUpdated: DateTime.now().toIso8601String(),
      );

      if (Platform.isMacOS) {
        await _saveMacOSWidgetData(WidgetDataKeys.scheduleData, data.toJsonString());
        await _reloadMacOSWidget('ScheduleWidget');
      } else {
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.scheduleData,
          data.toJsonString(),
        );
        await _updateWidgets(WidgetType.schedule);
      }
    } catch (e) {
      debugPrint('Error updating schedule widget: $e');
    }
  }

  Future<void> updateHomeworkWidget({
    required List<HomeworkItem> items,
    int maxItems = 10,
  }) async {
    if (kIsWeb) return;

    try {
      final sortedItems = List<HomeworkItem>.from(items)
        ..sort((a, b) => a.date.compareTo(b.date));

      final widgetItems = sortedItems
          .take(maxItems)
          .map((item) => WidgetHomeworkItem(
            subject: item.subject,
            text: _truncateText(item.text, 100),
            date: DateFormat('d MMM', 'ru').format(item.date),
            deadline: item.deadline != null
                ? DateFormat('d MMM HH:mm', 'ru').format(
                    DateTime.fromMillisecondsSinceEpoch((item.deadline! * 1000).toInt()))
                : null,
            hasFiles: item.files.isNotEmpty,
          ))
          .toList();

      final data = WidgetHomeworkData(
        items: widgetItems,
        lastUpdated: DateTime.now().toIso8601String(),
      );

      if (Platform.isMacOS) {
        await _saveMacOSWidgetData(WidgetDataKeys.homeworkData, data.toJsonString());
        await _reloadMacOSWidget('HomeworkWidget');
      } else {
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.homeworkData,
          data.toJsonString(),
        );
        await _updateWidgets(WidgetType.homework);
      }
    } catch (e) {
      debugPrint('Error updating homework widget: $e');
    }
  }

  Future<void> updateGradesWidget({
    required List<WidgetGrade> grades,
    required String periodName,
  }) async {
    if (kIsWeb) return;

    try {
      final data = WidgetGradesData(
        periodName: periodName,
        grades: grades,
        lastUpdated: DateTime.now().toIso8601String(),
      );

      if (Platform.isMacOS) {
        await _saveMacOSWidgetData(WidgetDataKeys.gradesData, data.toJsonString());
        await _reloadMacOSWidget('GradesWidget');
      } else {
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.gradesData,
          data.toJsonString(),
        );
        await _updateWidgets(WidgetType.grades);
      }
    } catch (e) {
      debugPrint('Error updating grades widget: $e');
    }
  }

  Future<void> updateAllWidgets() async {
    if (kIsWeb) return;

    try {
      if (Platform.isMacOS) {
        await _reloadMacOSWidgets();
      } else if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
      } else if (Platform.isAndroid) {
        await HomeWidget.updateWidget(androidName: _androidScheduleWidget);
        await HomeWidget.updateWidget(androidName: _androidHomeworkWidget);
        await HomeWidget.updateWidget(androidName: _androidGradesWidget);
      }
    } catch (e) {
      debugPrint('Error updating all widgets: $e');
    }
  }

  Future<void> _updateWidgets(WidgetType type) async {
    try {
      if (Platform.isIOS) {
        await HomeWidget.updateWidget(iOSName: _iOSWidgetName);
      } else if (Platform.isAndroid) {
        switch (type) {
          case WidgetType.schedule:
            await HomeWidget.updateWidget(androidName: _androidScheduleWidget);
            break;
          case WidgetType.homework:
            await HomeWidget.updateWidget(androidName: _androidHomeworkWidget);
            break;
          case WidgetType.grades:
            await HomeWidget.updateWidget(androidName: _androidGradesWidget);
            break;
        }
      }
    } catch (e) {
      debugPrint('Error updating widget: $e');
    }
  }

  Future<void> clearAllWidgetData() async {
    if (kIsWeb) return;

    try {
      if (Platform.isMacOS) {
        await _saveMacOSWidgetData(WidgetDataKeys.scheduleData, WidgetScheduleData.empty().toJsonString());
        await _saveMacOSWidgetData(WidgetDataKeys.homeworkData, WidgetHomeworkData.empty().toJsonString());
        await _saveMacOSWidgetData(WidgetDataKeys.gradesData, WidgetGradesData.empty().toJsonString());
        await _reloadMacOSWidgets();
      } else {
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.scheduleData,
          WidgetScheduleData.empty().toJsonString(),
        );
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.homeworkData,
          WidgetHomeworkData.empty().toJsonString(),
        );
        await HomeWidget.saveWidgetData<String>(
          WidgetDataKeys.gradesData,
          WidgetGradesData.empty().toJsonString(),
        );
        await updateAllWidgets();
      }
    } catch (e) {
      debugPrint('Error clearing widget data: $e');
    }
  }

  bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isIOS || Platform.isAndroid || Platform.isMacOS;
  }

  String _truncateText(String text, int maxLength) {
    if (text.length <= maxLength) return text;
    return '${text.substring(0, maxLength - 3)}...';
  }
}