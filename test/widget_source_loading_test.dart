import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reschool/providers/bell_schedule_provider.dart';
import 'package:reschool/providers/settings_provider.dart';
import 'package:reschool/providers/widget_config_provider.dart';
import 'package:reschool/services/api_service.dart';
import 'package:reschool/viewmodels/assignments_viewmodel.dart';
import 'package:reschool/viewmodels/diary_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    await api.logout();
    api.userId = 1;
    api.currentPrsId = 2;
    api.currentYearId = 3;
    api.isAuthenticated = true;
  });

  http.Response response(Object value) => http.Response(
    jsonEncode(value),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
  Map<String, dynamic> diary(String text) => {
    'lesson': [
      {
        'date': DateTime.now().millisecondsSinceEpoch,
        'unit': {'name': 'Математика'},
        'part': [
          {
            'cat': 'DZ',
            'variant': [
              {'id': 1, 'text': text},
            ],
          },
        ],
      },
    ],
  };

  test(
    'initial week always starts at midnight even when opened in the evening',
    () async {
      final bells = BellScheduleProvider();
      await bells.ready;
      final vm = DiaryViewModel(
        bells,
        initialDate: DateTime(2026, 9, 16, 22, 45),
        autoLoad: false,
      );
      expect(vm.currentWeek.first, DateTime(2026, 9, 14));
      expect(vm.currentWeek.last, DateTime(2026, 9, 20));
      vm.dispose();
      bells.dispose();
    },
  );

  test('late homework response cannot replace a newer load', () async {
    final settings = SettingsProvider();
    await settings.reloadCloudSettings();
    final vm = AssignmentsViewModel(settings);
    final first = Completer<http.Response>();
    final requested = Completer<void>();
    var count = 0;
    await http.runWithClient(
      () async {
        final oldLoad = vm.loadAssignments();
        await requested.future;
        await vm.loadAssignments();
        expect(vm.items.single.text, 'Новое задание');
        first.complete(response(diary('Старое задание')));
        await oldLoad;
        expect(vm.items.single.text, 'Новое задание');
        expect(vm.isLoading, false);
      },
      () => MockClient((request) async {
        if (request.url.path.contains('getLPartListPupil')) {
          return response({'result': []});
        }
        if (++count == 1) {
          requested.complete();
          return first.future;
        }
        return response(diary('Новое задание'));
      }),
    );
    vm.dispose();
    settings.dispose();
  });

  test(
    'logout clears homework and rejects a response already in flight',
    () async {
      final settings = SettingsProvider();
      await settings.reloadCloudSettings();
      final vm = AssignmentsViewModel(settings);
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      await http.runWithClient(
        () async {
          final load = vm.loadAssignments();
          await requested.future;
          await api.logout();
          pending.complete(response(diary('Чужое задание')));
          await load;
          expect(vm.items, isEmpty);
          expect(vm.isLoading, false);
          expect(vm.error, isNull);
        },
        () => MockClient((request) {
          requested.complete();
          return pending.future;
        }),
      );
      vm.dispose();
      settings.dispose();
    },
  );

  test('editing settings while they load preserves both edits and stored preferences', () async {
    SharedPreferences.setMockInitialValues({
      'widget_config': jsonEncode({
        'showTeacherInSchedule': false,
        'homeworkItemsCount': 7,
      }),
    });
    final config = WidgetConfigProvider();
    await Future.wait([
      config.setGradesEnabled(false),
      config.setShowDeadlineInHomework(false),
    ]);
    expect(config.showTeacherInSchedule, false);
    expect(config.homeworkItemsCount, 7);
    final saved = jsonDecode(
      (await SharedPreferences.getInstance()).getString('widget_config')!,
    );
    expect(saved['gradesEnabled'], false);
    expect(saved['showDeadlineInHomework'], false);
    config.dispose();
  });
}
