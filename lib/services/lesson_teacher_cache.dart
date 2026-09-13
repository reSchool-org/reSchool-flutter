import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/diary_models.dart';
import 'school_cache_policy.dart';

typedef LessonTeacherNames = ({String short, String full});

/// учителя восстанавливаем только для того же урока и владельца, одного названия предмета мало
class LessonTeacherCache {
  static const _prefix = 'diary_teacher_${SchoolCachePolicy.namespace}_';
  final DateTime Function() _now;

  LessonTeacherCache({DateTime Function()? now}) : _now = now ?? DateTime.now;

  String _key(String owner, PrsDiaryLesson lesson) =>
      '$_prefix${owner}_${lesson.orgId}_${lesson.groupId}_${lesson.unit?.id}_'
      '${lesson.id}_${lesson.date}';

  Future<Map<int, LessonTeacherNames>> resolve(
    List<PrsDiaryLesson> lessons, {
    required String? owner,
    required bool Function() isCurrent,
  }) async {
    final result = <int, LessonTeacherNames>{};
    final prefs = await SharedPreferences.getInstance();
    if (!isCurrent()) return result;
    // старый бессрочный кеш по названию предмета переносить нельзя
    await prefs.remove('diary_teacher_cache');
    final now = _now();
    for (final key in prefs.getKeys().where((k) => k.startsWith(_prefix))) {
      if (!isCurrent()) return {};
      if (_read(prefs, key, now) == null) await prefs.remove(key);
    }
    for (final lesson in lessons) {
      if (!isCurrent()) return {};
      if (lesson.id == null) continue;
      final names = (
        short: lesson.teacherShortName,
        full: lesson.teacherFullName,
      );
      final key = owner == null || lesson.date == null
          ? null
          : _key(owner, lesson);
      // явный список учителей, даже пустой, заменяет прежние данные
      if (lesson.hasTeacherAssignment) {
        result[lesson.id!] = names;
        if (key != null) {
          if (names.full.isEmpty) {
            await prefs.remove(key);
          } else {
            await prefs.setString(
              key,
              jsonEncode({
                'version': SchoolCachePolicy.version,
                'savedAt': now.millisecondsSinceEpoch,
                'short': names.short,
                'full': names.full,
              }),
            );
          }
        }
      } else {
        result[lesson.id!] = key == null
            ? names
            : _read(prefs, key, now) ?? names;
      }
    }
    return isCurrent() ? result : {};
  }

  LessonTeacherNames? _read(SharedPreferences prefs, String key, DateTime now) {
    try {
      final raw = prefs.getString(key);
      if (raw == null) return null;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      if (data['version'] != SchoolCachePolicy.version ||
          data['savedAt'] is! int ||
          data['short'] is! String ||
          data['full'] is! String ||
          (data['full'] as String).trim().isEmpty ||
          !SchoolCachePolicy.isFresh(
            DateTime.fromMillisecondsSinceEpoch(data['savedAt'] as int),
            now,
          )) {
        return null;
      }
      return (short: data['short'] as String, full: data['full'] as String);
    } catch (_) {
      return null;
    }
  }
}
