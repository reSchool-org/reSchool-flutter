import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reschool/services/api_service.dart';
import 'package:reschool/providers/settings_provider.dart';
import 'package:reschool/viewmodels/assignments_viewmodel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  const full =
      'Повторить времена present simple, present continuous, past simple. Повторить слова на странице 8';
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
    await api.logout();
    api.currentPrsId = 100;
    api.userId = 10;
    api.currentYearId = 2026;
    api.isAuthenticated = true;
  });
  tearDown(() async => api.logout());

  for (final samePart in [true, false]) {
    test(
      'превью ${samePart ? 'той же части не дублирует ДЗ' : 'другой части не скрывает отдельное ДЗ'}',
      () async {
        final settings = SettingsProvider();
        await settings.reloadCloudSettings();
        final model = AssignmentsViewModel(settings);
        addTearDown(model.dispose);
        addTearDown(settings.dispose);
        final date = DateTime.now().millisecondsSinceEpoch;
        await http.runWithClient(
          () => model.loadAssignments(),
          () => MockClient((request) async {
            final path = request.url.path;
            dynamic data;
            if (path.endsWith('/getPrsDiary')) {
              data = {
                'lesson': [
                  {
                    'id': 5,
                    'date': date,
                    'unit': {'name': 'Английский язык'},
                    'part': [
                      {
                        'id': 2,
                        'cat': 'DZ',
                        'variant': [
                          {'id': 1, 'text': '<p>$full</p>'},
                        ],
                      },
                    ],
                  },
                ],
              };
            } else if (path.endsWith('/getLPartListPupil')) {
              data = {
                'result': [
                  {
                    'partId': samePart ? 2 : 3,
                    'passDt': date,
                    'unitName': 'Английский язык',
                    'preview': full.substring(0, 65),
                  },
                ],
              };
            } else {
              fail('Unexpected request: $path');
            }
            return http.Response(
              jsonEncode(data),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        );
        expect(model.error, isNull);
        expect(model.items.length, samePart ? 1 : 2);
        expect(model.items.first.text, full);
        expect(model.items.first.partId, 2);
      },
    );
  }
}
