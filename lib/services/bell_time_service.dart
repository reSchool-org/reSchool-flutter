import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class ServerBellPreset {
  final int offsetSeconds;
  final Map<int, ({String start, String end})> lessons;

  ServerBellPreset(this.offsetSeconds, this.lessons);
}

/// время звонков берём из публичного сервиса, независимо от школьного сервера и данных входа
class BellTimeService {
  static final endpoint = Uri.parse('https://reschool.app/time');
  static const campusIds = ['fml30_shevchenko', 'fml30_7liniya'];
  static const cacheKey = 'bell_server_time_v1';
  static const interval = Duration(days: 1);

  final http.Client _client;
  final DateTime Function() _now;
  Map<String, ServerBellPreset> presets = {};
  DateTime? lastSyncedAt;
  DateTime? _lastAttempt;
  Duration _clockOffset = Duration.zero;
  Future<void>? _pending;
  bool _disposed = false;
  String? error;

  BellTimeService({http.Client? client, DateTime Function()? now})
    : _client = client ?? http.Client(),
      _now = now ?? DateTime.now;

  DateTime get moscowNow =>
      _now().toUtc().add(_clockOffset).add(const Duration(hours: 3));

  /// Перевод школьного времени в момент по часам устройства для обновления виджета.
  DateTime fromMoscowTime(DateTime wallTime) => DateTime.utc(
    wallTime.year,
    wallTime.month,
    wallTime.day,
    wallTime.hour,
    wallTime.minute,
    wallTime.second,
  ).subtract(const Duration(hours: 3)).subtract(_clockOffset).toLocal();
  bool get isStale =>
      lastSyncedAt == null ||
      _now().difference(lastSyncedAt!) >= interval ||
      _now().isBefore(lastSyncedAt!);

  Future<void> loadCache() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final cached = prefs.getString(cacheKey);
      if (cached == null) return;
      final data = jsonDecode(cached) as Map<String, dynamic>;
      final parsed = _parse(data['payload'] as Map<String, dynamic>);
      final savedAt = DateTime.fromMillisecondsSinceEpoch(
        data['savedAt'] as int,
      );
      final offset = Duration(milliseconds: data['clockOffsetMs'] as int);
      presets = parsed;
      lastSyncedAt = savedAt;
      _clockOffset = offset;
    } catch (_) {
      // битый кеш не должен мешать загрузке встроенного расписания
    }
  }

  Future<void> syncIfDue() {
    if (_disposed) return Future.value();
    if (_pending != null) return _pending!;
    if (!isStale) return Future.value();
    final sinceAttempt = _lastAttempt == null
        ? null
        : _now().difference(_lastAttempt!);
    if (sinceAttempt != null &&
        !sinceAttempt.isNegative &&
        sinceAttempt < const Duration(hours: 1)) {
      return Future.value();
    }
    return _pending = _fetch().whenComplete(() => _pending = null);
  }

  Future<void> _fetch() async {
    _lastAttempt = _now();
    final stopwatch = Stopwatch()..start();
    try {
      final response = await _client
          .get(endpoint, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 8));
      final receivedAt = _now();
      if (response.statusCode != 200 || response.bodyBytes.length > 32768) {
        throw const FormatException('Invalid bell response');
      }
      final payload = jsonDecode(response.body) as Map<String, dynamic>;
      final parsed = _parse(payload);
      final serverTime = DateTime.fromMillisecondsSinceEpoch(
        payload['serverTimeMs'] as int,
        isUtc: true,
      );
      if (serverTime.year < 2024 || serverTime.year > 2100) {
        throw const FormatException('Invalid server clock');
      }
      final offset = serverTime
          .add(Duration(microseconds: stopwatch.elapsedMicroseconds ~/ 2))
          .difference(receivedAt.toUtc());
      if (_disposed) return;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        cacheKey,
        jsonEncode({
          'payload': payload,
          'savedAt': receivedAt.millisecondsSinceEpoch,
          'clockOffsetMs': offset.inMilliseconds,
        }),
      );
      presets = parsed;
      lastSyncedAt = receivedAt;
      _clockOffset = offset;
      error = null;
    } catch (_) {
      error = 'Не удалось связаться с reschool.app';
    }
  }

  static Map<String, ServerBellPreset> _parse(Map<String, dynamic> payload) {
    if (payload['version'] != 1 || payload['timezone'] != 'Europe/Moscow') {
      throw const FormatException('Unsupported bell payload');
    }
    final raw = payload['presets'] as Map<String, dynamic>;
    final result = <String, ServerBellPreset>{};
    final pattern = RegExp(r'^(?:[01]\d|2[0-3]):[0-5]\d(?::[0-5]\d)?$');
    int seconds(String value) {
      if (!pattern.hasMatch(value)) throw const FormatException('Invalid time');
      final parts = value.split(':').map(int.parse).toList();
      return parts[0] * 3600 +
          parts[1] * 60 +
          (parts.length == 3 ? parts[2] : 0);
    }

    for (final id in campusIds) {
      final preset = raw[id] as Map<String, dynamic>;
      final offset = preset['offsetSeconds'] as int;
      if (offset.abs() > 3600) throw const FormatException('Invalid offset');
      final lessons = preset['lessons'] as Map<String, dynamic>;
      if (lessons.isEmpty || lessons.length > 16) {
        throw const FormatException('Invalid lessons');
      }
      final parsed = <int, ({String start, String end})>{};
      final numbers = lessons.keys.map(int.parse).toList()..sort();
      var previousEnd = -1;
      for (final number in numbers) {
        if (number < 0 || number > 15) {
          throw const FormatException('Invalid lesson number');
        }
        final lesson = lessons[number.toString()] as Map<String, dynamic>;
        final start = lesson['start'] as String;
        final end = lesson['end'] as String;
        final startSec = seconds(start), endSec = seconds(end);
        if (startSec < previousEnd ||
            endSec <= startSec ||
            startSec + offset < 0 ||
            endSec + offset >= 86400) {
          throw const FormatException('Invalid lesson interval');
        }
        previousEnd = endSec;
        parsed[number] = (start: start, end: end);
      }
      result[id] = ServerBellPreset(offset, parsed);
    }
    return result;
  }

  void dispose() {
    _disposed = true;
    _client.close();
  }
}
