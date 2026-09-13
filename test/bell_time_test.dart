import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reschool/providers/bell_schedule_provider.dart';
import 'package:reschool/services/bell_time_service.dart';
import 'package:reschool/utils/time_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> payload(DateTime now, {int offset = 126}) => {
  'version': 1,
  'revision': 1,
  'timezone': 'Europe/Moscow',
  'serverTimeMs': now.millisecondsSinceEpoch,
  'presets': {
    'fml30_shevchenko': {
      'offsetSeconds': offset,
      'lessons': {
        '1': {'start': '08:50:07', 'end': '09:35:07'},
      },
    },
    'fml30_7liniya': {
      'offsetSeconds': -12,
      'lessons': {
        '1': {'start': '08:30', 'end': '09:15'},
      },
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late DateTime current;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    current = DateTime.utc(2026, 9, 14, 6);
  });

  test(
    'anonymous fixed endpoint, one refresh per 24 hours, restart uses cache',
    () async {
      var requests = 0;
      http.Client client() => MockClient((request) async {
        requests++;
        expect(request.url.toString(), 'https://reschool.app/time');
        expect(request.headers['Accept'], 'application/json');
        expect(
          request.headers.keys.any(
            (k) =>
                k.toLowerCase().contains('token') ||
                k.toLowerCase() == 'authorization',
          ),
          isFalse,
        );
        return http.Response(jsonEncode(payload(current)), 200);
      });
      final service = BellTimeService(client: client(), now: () => current);
      addTearDown(service.dispose);
      await service.syncIfDue();
      expect(requests, 1);
      current = current.add(const Duration(hours: 23, minutes: 59));
      await service.syncIfDue();
      expect(requests, 1);
      final restarted = BellTimeService(client: client(), now: () => current);
      addTearDown(restarted.dispose);
      await restarted.loadCache();
      await restarted.syncIfDue();
      expect(requests, 1);
      expect(restarted.presets['fml30_shevchenko']!.offsetSeconds, 126);
      current = current.add(const Duration(minutes: 1));
      await restarted.syncIfDue();
      expect(requests, 2);
    },
  );

  test(
    'offline or invalid responses retain timings and retry after an hour',
    () async {
      var requests = 0;
      final service = BellTimeService(
        now: () => current,
        client: MockClient((_) async {
          requests++;
          return requests == 1
              ? http.Response(jsonEncode(payload(current)), 200)
              : http.Response('<html>captcha</html>', 200);
        }),
      );
      addTearDown(service.dispose);
      await service.syncIfDue();
      final saved = service.lastSyncedAt;
      current = current.add(const Duration(days: 1));
      await service.syncIfDue();
      expect(service.lastSyncedAt, saved);
      expect(service.presets['fml30_shevchenko']!.offsetSeconds, 126);
      expect(service.error, isNotNull);
      await service.syncIfDue();
      expect(requests, 2);
      current = current.add(const Duration(hours: 1));
      await service.syncIfDue();
      expect(requests, 3);
    },
  );

  test('simultaneous refreshes share one request', () async {
    final response = Completer<http.Response>();
    var requests = 0;
    final service = BellTimeService(
      now: () => current,
      client: MockClient((_) {
        requests++;
        return response.future;
      }),
    );
    addTearDown(service.dispose);
    final first = service.syncIfDue();
    final second = service.syncIfDue();
    response.complete(http.Response(jsonEncode(payload(current)), 200));
    await Future.wait([first, second]);
    expect(requests, 1);
  });

  test(
    'clock correction and Moscow timezone are used for bell timers',
    () async {
      final serverNow = current;
      current = current.subtract(const Duration(minutes: 5));
      final service = BellTimeService(
        now: () => current,
        client: MockClient(
          (_) async => http.Response(jsonEncode(payload(serverNow)), 200),
        ),
      );
      addTearDown(service.dispose);
      await service.syncIfDue();
      expect(
        service.moscowNow
            .difference(serverNow.add(const Duration(hours: 3)))
            .inSeconds
            .abs(),
        lessThan(2),
      );
    },
  );

  test('server mode uses lesson seconds; manual offsets remain separate per campus', () async {
    final provider = BellScheduleProvider(
      startTimers: false,
      bellTimeService: BellTimeService(
        now: () => current,
        client: MockClient(
          (_) async => http.Response(jsonEncode(payload(current)), 200),
        ),
      ),
    );
    addTearDown(provider.dispose);
    await provider.ready;
    await provider.applyPreset('fml30_shevchenko');
    expect(provider.usesServerTime, isTrue);
    expect(provider.getLessonTime(1)!.start, '08:52:13');
    await provider.setServerSync(false);
    expect(provider.timeOffset, 0);
    await provider.setTimeOffset(35);
    expect(provider.getLessonTime(1)!.start, '08:50:35');
    await provider.applyPreset('fml30_7liniya');
    expect(provider.usesServerTime, isTrue);
    expect(provider.getLessonTime(1)!.start, '08:29:48');
    await provider.setTimeOffset(-5);
    await provider.applyPreset('fml30_shevchenko');
    expect(provider.usesServerTime, isFalse);
    expect(provider.timeOffset, 35);
    await provider.setServerSync(true);
    expect(provider.timeOffset, 126);
    await provider.setServerSync(false);
    expect(provider.timeOffset, 35);
  });

  test(
    'legacy correction is retained only for selected campus manual mode',
    () async {
      SharedPreferences.setMockInitialValues({
        'bell_schedule_preset': 'fml30_shevchenko',
        'bell_schedule_offset': 126,
      });
      final provider = BellScheduleProvider(
        startTimers: false,
        bellTimeService: BellTimeService(
          now: () => current,
          client: MockClient(
            (_) async =>
                http.Response(jsonEncode(payload(current, offset: 150)), 200),
          ),
        ),
      );
      addTearDown(provider.dispose);
      await provider.ready;
      expect(provider.timeOffset, 150);
      await provider.setServerSync(false);
      expect(provider.timeOffset, 126);
      await provider.applyPreset('fml30_7liniya');
      await provider.setServerSync(false);
      expect(provider.timeOffset, 0);
    },
  );

  test('weekday campus uses its own mode and offset', () async {
    final provider = BellScheduleProvider(
      startTimers: false,
      bellTimeService: BellTimeService(
        now: () => current,
        client: MockClient(
          (_) async => http.Response(jsonEncode(payload(current)), 200),
        ),
      ),
    );
    addTearDown(provider.dispose);
    await provider.ready;
    await provider.setWeekdayPreset(DateTime.monday, 'fml30_shevchenko');
    await provider.setWeekdayPreset(DateTime.tuesday, 'fml30_7liniya');
    await provider.setAutoScheduleEnabled(true);
    expect(provider.timeOffset, 126);
    current = current.add(const Duration(days: 1));
    expect(provider.effectivePresetId, 'fml30_7liniya');
    expect(provider.timeOffset, -12);
  });

  test('first offline launch has no baked-in Shevchenko delay', () async {
    SharedPreferences.setMockInitialValues({
      'bell_schedule_preset': 'fml30_shevchenko',
    });
    final provider = BellScheduleProvider(
      startTimers: false,
      bellTimeService: BellTimeService(
        client: MockClient((_) async => throw http.ClientException('offline')),
      ),
    );
    addTearDown(provider.dispose);
    await provider.ready;
    expect(provider.timeOffset, 0);
    expect(provider.getLessonTime(1)!.start, '08:50');
    expect(provider.syncStatus, contains('Сервер недоступен'));
  });

  test('seconds survive positive and negative time corrections', () {
    expect(TimeUtils.addSeconds('08:50:07', 126), '08:52:13');
    expect(TimeUtils.addSeconds('00:00:05', -10), '23:59:55');
  });
}
