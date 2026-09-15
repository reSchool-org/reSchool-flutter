import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reschool/models/student_context.dart';
import 'package:reschool/models/account.dart';
import 'package:reschool/services/api_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> parentState() => {
  'userId': 10,
  'user': {
    'prsId': 100,
    'currentPosition': {
      'posTypeCode': 'P',
      'myChildren': [
        {'prsId': 200, 'userData': []},
        {
          'prsId': 300,
          'isDefaultChild': 1,
          'userData': [
            {'userId': 29, 'orgIsReady': 1, 'yearState': 'ARC'},
            {'userId': 30, 'orgIsReady': 1, 'yearState': 'CURR'},
            {'userId': 31, 'orgIsReady': 1, 'yearState': 'PLAN'},
          ],
        },
      ],
    },
  },
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final api = ApiService();
  const storage = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() async {
    SharedPreferences.setMockInitialValues({
      'eschool_cli_version': '3.0.0',
      'eschool_cli_version_at': DateTime.now().millisecondsSinceEpoch,
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(storage, (_) async => null);
    await api.logout();
  });
  tearDown(() async => api.logout());

  test('выбирает ребёнка по умолчанию и его текущую школу', () {
    final student = StudentContext.fromState(parentState());
    expect(student.prsId, 300);
    expect(student.userId, 30);
  });

  test('родитель без детей не становится учеником', () {
    final state = parentState();
    state['user']['currentPosition']['myChildren'] = [];
    expect(StudentContext.fromState(state).prsId, isNull);
    expect(StudentContext.fromState(state).userId, isNull);
  });

  test('использует первого ребёнка, если основной не выбран', () {
    final state = parentState();
    state['user']['currentPosition']['myChildren'][1]['isDefaultChild'] = 0;
    expect(StudentContext.fromState(state).prsId, 200);
    expect(StudentContext.fromState(state).userId, isNull);
  });

  test(
    'учебные запросы идут от ребёнка, профиль и сессия от родителя',
    () async {
      final saved = jsonEncode(
        Account(
          username: 'parent',
          password: '',
          fullName: 'Parent',
          prsId: 100,
          sessionCookie: 'saved-session',
        ).toJson(),
      );
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            storage,
            (call) async =>
                call.method == 'read' &&
                    call.arguments['key'] == 'saved_account'
                ? saved
                : null,
          );
      final paths = <String>[];
      await http.runWithClient(
        () async {
          await api.init();
          expect(api.currentPrsId, 100);
          expect(api.userId, 10);
          expect(api.studentPrsId, 300);
          expect(api.studentUserId, 30);
          expect(api.account!.prsId, 100);
          await api.getPrsDiary(1, 2);
          await api.getClassByUser();
          await api.getDiaryUnits(5);
          await api.getDiaryPeriod(5);
          expect(await api.getCurrentYearId(), 2026);
          await api.getPupilUnits(api.studentPrsId!, 2026);
          await api.getLPartListPupil(1, 2, 2026);
          await api.getLPartPupil(8);
          await api.getProfileNew(api.currentPrsId!);
        },
        () => MockClient((request) async {
          final path = request.url.path;
          final query = request.url.queryParameters;
          paths.add(path);
          dynamic body = {};
          if (path.endsWith('/state')) {
            body = parentState();
          } else if (path.endsWith('/getClassByUser')) {
            expect(query['userId'], '30');
            body = [];
          } else if (path.contains('getDiaryUnits') ||
              path.contains('getDiaryPeriod_')) {
            expect(query['userId'], '30');
            body = {'result': []};
          } else if (path.contains('/student/')) {
            expect(query['prsId'], '300');
            body = {
              'result': path.endsWith('/getLPartPupil') ? [{}] : [],
            };
          } else if (path.endsWith('/getProfile_new')) {
            body = {
              'pupil': [
                {'yearId': 2026},
              ],
            };
            expect(
              query['prsId'],
              paths.where((p) => p.endsWith('/getProfile_new')).length == 1
                  ? '300'
                  : '100',
            );
          } else {
            fail('Unexpected request: $path');
          }
          return http.Response(jsonEncode(body), 200);
        }),
      );
      await api.logout();
      expect(api.studentPrsId, isNull);
      expect(api.studentUserId, isNull);
    },
  );
}
