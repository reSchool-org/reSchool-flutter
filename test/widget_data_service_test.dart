import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:reschool/services/widget_data_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unsupported desktop never invokes native home widget plugins',
    () async {
      await initializeDateFormatting('ru');
      final calls = <MethodCall>[];
      const channels = [
        MethodChannel('home_widget'),
        MethodChannel('com.magisky.reschoolbeta/widgets'),
      ];
      for (final channel in channels) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return true;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
      }
      final service = WidgetDataService();
      expect(service.isSupported, isFalse);
      await service.initialize();
      await service.updateScheduleWidget(
        lessons: [],
        date: DateTime(2026, 9, 11),
      );
      await service.updateHomeworkWidget(items: []);
      await service.updateGradesWidget(grades: [], periodName: 'Четверть');
      await service.updateAllWidgets();
      await service.clearAllWidgetData();
      expect(calls, isEmpty);
    },
    skip: !(Platform.isLinux || Platform.isWindows),
  );
}
