import '../models/widget_models.dart';
import '../providers/bell_schedule_provider.dart';
import '../providers/settings_provider.dart';
import '../viewmodels/assignments_viewmodel.dart';
import '../viewmodels/diary_viewmodel.dart';
import '../viewmodels/marks_viewmodel.dart';
import 'api_service.dart';
import 'widget_data_service.dart';

/// обновляем все включённые виджеты независимо от открытой вкладки
class WidgetSyncService {
  static final instance = WidgetSyncService._();
  WidgetSyncService._();

  Future<void>? _active;
  int? _activeEpoch;
  DateTime? _lastSuccess;
  int? _lastEpoch;

  Future<void> refresh({
    required BellScheduleProvider bells,
    required SettingsProvider settings,
    required WidgetConfig config,
    bool force = false,
  }) {
    final api = ApiService();
    if (!WidgetDataService().isSupported || !api.isAuthenticated) {
      return Future.value();
    }
    final epoch = api.identityEpoch;
    if (_active != null && _activeEpoch == epoch) return _active!;
    if (!force &&
        _lastEpoch == epoch &&
        _lastSuccess != null &&
        DateTime.now().difference(_lastSuccess!) < const Duration(minutes: 2)) {
      return Future.value();
    }
    _activeEpoch = epoch;
    final operation = _refresh(bells, settings, config, force, epoch);
    _active = operation;
    return operation.whenComplete(() {
      if (identical(_active, operation)) _active = null;
    });
  }

  Future<void> _refresh(
    BellScheduleProvider bells,
    SettingsProvider settings,
    WidgetConfig config,
    bool force,
    int epoch,
  ) async {
    if (!force && !await WidgetDataService().hasInstalledWidgets()) return;
    await bells.ready;
    if (epoch != ApiService().identityEpoch) return;
    final diary = DiaryViewModel(bells, autoLoad: false);
    final now = bells.now;
    final today = DateTime(now.year, now.month, now.day);
    final monday = today.subtract(Duration(days: today.weekday - 1));
    diary.currentWeek = List.generate(
      14,
      (index) => monday.add(Duration(days: index)),
    );
    final homework = AssignmentsViewModel(settings);
    final grades = MarksViewModel(bells);
    final widgets = WidgetDataService();
    widgets.lastError = null;
    try {
      await Future.wait([
        if (config.scheduleEnabled || config.homeworkEnabled)
          diary.loadSchedule(enrichHomework: false, findNextSchoolDay: true),
        if (config.homeworkEnabled) homework.loadAssignments(forWidgets: true),
        if (config.gradesEnabled) grades.loadPeriods(forceRefresh: true),
      ]);
      if (epoch != ApiService().identityEpoch) return;
      if (force) {
        await widgets.updateAllWidgets();
      } else {
        await widgets.flush();
      }
      final error =
          diary.error ?? homework.error ?? grades.error ?? widgets.lastError;
      if (error != null) throw StateError(error.toString());
      _lastSuccess = DateTime.now();
      _lastEpoch = epoch;
    } finally {
      diary.dispose();
      homework.dispose();
      grades.dispose();
    }
  }
}
