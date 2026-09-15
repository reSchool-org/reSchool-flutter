import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reschool/models/homework_models.dart';
import 'package:reschool/models/lesson_view_model.dart';
import 'package:reschool/models/widget_models.dart';
import 'package:reschool/services/widget_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final now = DateTime(2026, 9, 14, 12);
  late List<MethodCall> calls;
  late Map<String, Map<String, dynamic>> data;
  Future<void> Function(MethodCall)? beforeCall;

  setUp(() {
    calls = [];
    data = {};
    beforeCall = null;
    SharedPreferences.setMockInitialValues({});
    for (final name in ['home_widget', 'com.magisky.reschoolbeta/widgets']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async {
            calls.add(call);
            await beforeCall?.call(call);
            if (call.method == 'saveWidgetData') {
              final args = call.arguments as Map;
              data[(args['id'] ?? args['key']) as String] = jsonDecode(
                args['data'] as String,
              );
            }
            return true;
          });
    }
  });

  tearDown(() {
    for (final name in ['home_widget', 'com.magisky.reschoolbeta/widgets']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null);
    }
  });

  WidgetDataService service(TargetPlatform platform) =>
      WidgetDataService.forTesting(platform, now: () => now);
  HomeworkItem homework(
    DateTime date, {
    String text = 'Задание',
    double? deadline,
    int? partId,
  }) => HomeworkItem(
    date: date,
    subject: 'Математика',
    text: text,
    files: [],
    deadline: deadline,
    partId: partId,
  );
  LessonViewModel lesson(int number) => LessonViewModel(
    id: number,
    num: number,
    subject: 'Предмет $number',
    topic: '',
    teacher: 'Учитель',
    teacherFull: 'Учитель',
    homework: '',
    homeworkFiles: [],
    startTime: '08:30',
    endTime: '09:15',
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.android,
    TargetPlatform.macOS,
  ]) {
    test(
      '$platform reloads actual kinds only after saving each snapshot',
      () async {
        final widgets = service(platform);
        await widgets.updateScheduleWidget(lessons: [lesson(1)], date: now);
        await widgets.updateHomeworkWidget(items: [homework(now)]);
        await widgets.updateGradesWidget(grades: [], periodName: 'Четверть');
        final reloads = calls
            .where(
              (c) =>
                  c.method ==
                  (platform == TargetPlatform.macOS
                      ? 'reloadWidget'
                      : 'updateWidget'),
            )
            .toList();
        expect(reloads, hasLength(4));
        for (var i = 0; i < 4; i++) {
          final kind = [
            'ScheduleWidget',
            'HomeworkWidget',
            'HomeworkWidget',
            'GradesWidget',
          ][i];
          final args = reloads[i].arguments as Map;
          expect(
            args[platform == TargetPlatform.macOS
                ? 'kind'
                : platform == TargetPlatform.iOS
                ? 'ios'
                : 'android'],
            platform == TargetPlatform.android ? 'widgets.$kind' : kind,
          );
          if (i != 1) {
            expect(
              calls[calls.indexOf(reloads[i]) - 1].method,
              'saveWidgetData',
            );
          }
        }
        if (platform == TargetPlatform.iOS) {
          expect(calls.first.method, 'setAppGroupId');
        }
      },
    );
  }

  test('homework excludes past days, sorts, deduplicates and handles both deadline units', () async {
    final widgets = service(TargetPlatform.iOS);
    final deadline = DateTime(2026, 9, 15, 8, 30);
    final duplicate = homework(
      now,
      text: '<p>Решить &amp; проверить</p>',
      deadline: deadline.millisecondsSinceEpoch.toDouble(),
    );
    await widgets.updateHomeworkWidget(
      items: [
        homework(
          now.add(const Duration(days: 1)),
          deadline: deadline.millisecondsSinceEpoch / 1000,
        ),
        duplicate,
        duplicate,
        homework(now.subtract(const Duration(days: 1))),
      ],
    );
    final items = data[WidgetDataKeys.homeworkData]!['items'] as List;
    expect(items, hasLength(2));
    expect(items.first['dateISO'], '2026-09-14');
    expect(items.first['text'], 'Решить & проверить');
    expect(items.first['deadline'], items.last['deadline']);
    expect(items.first['deadline'], contains('08:30'));
    expect(items.first['deadline'], isNot(contains('58000')));
  });

  test(
    'lesson snapshots are sorted, exclude gaps and retain upcoming days',
    () async {
      final widgets = service(TargetPlatform.iOS);
      final next = DateTime(2026, 9, 21);
      await widgets.updateScheduleWidget(
        lessons: [
          lesson(3),
          lesson(1),
          LessonViewModel.placeholder(num: 2, startTime: '', endTime: ''),
        ],
        date: now,
        days: {
          next: [lesson(5)],
        },
      );
      await widgets.updateScheduleWidget(lessons: [lesson(1)], date: now);
      final saved = data[WidgetDataKeys.scheduleData]!;
      expect((saved['lessons'] as List).single['num'], 1);
      expect((saved['days'] as List).last['dateISO'], '2026-09-21');
      expect((saved['days'] as List).last['lessons'][0]['num'], 5);
    },
  );

  for (final platform in [
    TargetPlatform.iOS,
    TargetPlatform.macOS,
    TargetPlatform.android,
  ]) {
    test(
      'grades prioritize mark counts and retain all subjects on $platform',
      () async {
        final widgets = service(platform);
        final grades = [
          WidgetGrade(subject: 'Алгебра', average: '0.00', totalMarks: 0),
          WidgetGrade(subject: 'История', average: '5.00', totalMarks: 1),
          WidgetGrade(subject: 'Физика', average: '3.00', totalMarks: 7),
          WidgetGrade(subject: 'Химия', average: '4.00', totalMarks: 7),
          WidgetGrade(subject: 'География', average: '4.50', totalMarks: 3),
          WidgetGrade(subject: 'Без данных', average: '-'),
          for (var i = 0; i < 12; i++)
            WidgetGrade(subject: 'Предмет $i', average: '-', totalMarks: 0),
        ];
        await widgets.updateGradesWidget(
          grades: grades,
          periodName: '1 четверть',
        );
        final saved = data[WidgetDataKeys.gradesData]!;
        final subjects = saved['grades'] as List;
        expect(subjects, hasLength(18));
        expect(subjects.take(6).map((s) => s['subject']), [
          'Физика',
          'Химия',
          'География',
          'История',
          'Алгебра',
          'Без данных',
        ]);
        expect(subjects.take(4).map((s) => s['totalMarks']), [7, 7, 3, 1]);
        expect(saved['periodName'], '1 четверть');
        expect(grades.first.subject, 'Алгебра');
      },
    );
  }

  test(
    'schedule publishes last bell and schedules both widgets at that instant',
    () async {
      final widgets = service(TargetPlatform.android);
      final end = DateTime(now.year, now.month, now.day, 14, 45, 30);
      await widgets.updateScheduleWidget(
        lessons: [
          lesson(1),
          lesson(3).copyWith(endTime: '14:45:30'),
        ],
        date: now,
      );
      final saved = data[WidgetDataKeys.scheduleData]!;
      expect(saved['schoolEndMs'], end.millisecondsSinceEpoch);
      expect(
        saved['dayStartMs'],
        DateTime(now.year, now.month, now.day).millisecondsSinceEpoch,
      );
      final scheduled = calls
          .where((call) => call.method == 'scheduleWidgetUpdates')
          .toList();
      expect(scheduled, hasLength(2));
      for (final call in scheduled) {
        expect(
          (call.arguments as Map).values.toString(),
          contains(end.millisecondsSinceEpoch.toString()),
        );
      }
    },
  );

  test('unknown last bell leaves school end unset and long holidays retain next lessons', () async {
    final widgets = service(TargetPlatform.iOS);
    final nextTerm = DateTime(2027, 1, 11);
    await widgets.updateScheduleWidget(
      lessons: [
        lesson(1),
        lesson(8).copyWith(endTime: ''),
      ],
      date: now,
      days: {
        nextTerm: [lesson(1)],
      },
    );
    final saved = data[WidgetDataKeys.scheduleData]!;
    expect(saved['schoolEndMs'], isNull);
    expect((saved['days'] as List).last['dateISO'], '2027-01-11');
  });

  test(
    'today cannot exhaust the homework cache before tomorrow is saved',
    () async {
      final widgets = service(TargetPlatform.iOS);
      final tomorrow = now.add(const Duration(days: 1));
      await widgets.updateHomeworkWidget(
        items: [
          for (var i = 0; i < 25; i++) homework(now, text: 'Сегодня $i'),
          homework(tomorrow, text: 'Завтра'),
        ],
      );
      final saved = data[WidgetDataKeys.homeworkData]!['items'] as List;
      expect(saved, hasLength(21));
      expect(saved.last['text'], 'Завтра');
    },
  );

  test('unchanged payload does not issue duplicate native reloads', () async {
    final widgets = service(TargetPlatform.iOS);
    final grades = [WidgetGrade(subject: 'Физика', average: '4,7')];
    await widgets.updateGradesWidget(grades: grades, periodName: '1 четверть');
    final count = calls.length;
    await widgets.updateGradesWidget(grades: grades, periodName: '1 четверть');
    expect(calls.length, count);
  });

  test('logout supersedes queued work and does not suppress a later identical payload', () async {
    final widgets = service(TargetPlatform.iOS);
    await widgets.initialize();
    final started = Completer<void>();
    final release = Completer<void>();
    beforeCall = (call) async {
      if (call.method == 'saveWidgetData' &&
          (call.arguments as Map)['id'] == WidgetDataKeys.gradesData &&
          !started.isCompleted) {
        started.complete();
        await release.future;
      }
    };
    final grades = [WidgetGrade(subject: 'Физика', average: '5')];
    final first = widgets.updateGradesWidget(grades: grades, periodName: '1');
    await started.future;
    final pending = widgets.updateHomeworkWidget(items: [homework(now)]);
    final clear = widgets.clearAllWidgetData();
    release.complete();
    await Future.wait([first, pending, clear]);
    expect(data[WidgetDataKeys.gradesData]!['grades'], isEmpty);
    expect(data[WidgetDataKeys.homeworkData]!['items'], isEmpty);
    expect(data[WidgetDataKeys.scheduleData]!['lessons'], isEmpty);
    await widgets.updateGradesWidget(grades: grades, periodName: '1');
    expect(data[WidgetDataKeys.gradesData]!['grades'], hasLength(1));
  });

  test(
    'failed publication is retryable and settings update native storage',
    () async {
      final widgets = service(TargetPlatform.macOS);
      await widgets.initialize();
      beforeCall = (call) async {
        if (call.method == 'reloadWidget') {
          throw PlatformException(code: 'temporary');
        }
      };
      await widgets.updateGradesWidget(grades: [], periodName: '1');
      expect(widgets.lastError, isA<PlatformException>());
      beforeCall = null;
      await widgets.updateGradesWidget(grades: [], periodName: '1');
      await widgets.updateConfiguration(
        WidgetConfig(showTeacherInSchedule: false, homeworkItemsCount: 3),
      );
      expect(
        data[WidgetDataKeys.widgetConfig]!['showTeacherInSchedule'],
        false,
      );
      expect(data[WidgetDataKeys.widgetConfig]!['homeworkItemsCount'], 3);
      await widgets.updateAppearance(accent: Colors.teal, mode: ThemeMode.dark);
      expect(data['widget_appearance']!['mode'], 'dark');
      expect(
        data['widget_appearance']!['light']['background'],
        isNot(data['widget_appearance']!['dark']['background']),
      );
    },
  );
}
