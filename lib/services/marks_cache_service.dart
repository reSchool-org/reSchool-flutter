import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'widget_data_service.dart';
import 'school_cache_policy.dart';

/// запись оценок и обновление виджетов выполняются по порядку при смене аккаунта
class MarksCacheService extends ChangeNotifier {
  static final MarksCacheService _instance = MarksCacheService._();
  factory MarksCacheService() => _instance;
  MarksCacheService._();

  int _generation = 0;
  int get generation => _generation;
  Future<void> _pending = Future.value();

  Future<void> _enqueue(Future<void> Function() operation) {
    final result = _pending.then((_) => operation());
    // ошибка записи не должна мешать последующей очистке при выходе
    _pending = result.catchError((Object _) {});
    return result;
  }

  Future<void> writeIfCurrent(int generation, Future<void> Function() write) {
    return _enqueue(() async {
      if (generation == _generation) await write();
    });
  }

  /// у старых данных виджета нет владельца, даже если в старой версии уже вышли из аккаунта
  Future<void> migrateLegacyData() {
    return _enqueue(() async {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getInt('marksCacheSchemaVersion') ==
          SchoolCachePolicy.version) {
        return;
      }
      await _clearPersisted();
      await prefs.setInt('marksCacheSchemaVersion', SchoolCachePolicy.version);
    });
  }

  Future<void> _clearPersisted() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      for (final key in prefs.getKeys().where(
        (k) => k.startsWith('marks_cache_'),
      )) {
        await prefs.remove(key);
      }
      await prefs.remove('lastSelectedPeriodId');
    } finally {
      await WidgetDataService().clearAllWidgetData();
    }
  }

  Future<void> invalidate() {
    _generation++;
    // видимое состояние чистим сразу, хранилище очищаем после прежних записей
    notifyListeners();
    return _enqueue(_clearPersisted);
  }
}
