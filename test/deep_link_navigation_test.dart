import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:reschool/l10n/app_localizations.dart';
import 'package:reschool/models/lesson_view_model.dart';
import 'package:reschool/providers/bell_schedule_provider.dart';
import 'package:reschool/providers/custom_homework_provider.dart';
import 'package:reschool/providers/settings_provider.dart';
import 'package:reschool/screens/diary_screen.dart';
import 'package:reschool/screens/home_screen.dart';
import 'package:reschool/screens/chat_detail_screen.dart';
import 'package:reschool/providers/widget_config_provider.dart';
import 'package:reschool/services/api_service.dart';
import 'package:reschool/services/app_link_inbox.dart';
import 'package:reschool/services/deep_link_handler.dart';
import 'package:reschool/services/diary_navigation_service.dart';
import 'package:reschool/viewmodels/diary_viewmodel.dart';
import 'package:reschool/widgets/lesson_card.dart';

class DelayedDiary extends DiaryViewModel {
  DelayedDiary(super.bellScheduleProvider)
    : super(initialDate: DateTime(2026, 9, 14), autoLoad: false) {
    isLoading = true;
  }

  @override
  Future<void> loadSchedule({
    bool enrichHomework = true,
    bool findNextSchoolDay = false,
  }) async {
    isLoading = true;
    error = null;
    notifyListeners();
  }

  void finish(
    DateTime date, {
    int id = 42,
    String subject = 'Физика',
    String? failure,
  }) {
    isLoading = false;
    error = failure;
    if (failure == null) {
      lessons['${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}'] =
          [
            LessonViewModel(
              id: id,
              num: 1,
              subject: subject,
              topic: 'Тема',
              teacher: '',
              teacherFull: '',
              homework: 'Решить задачу 42',
              homeworkFiles: [],
              mark: '5',
              startTime: '09:00',
              endTime: '09:45',
            ),
          ];
    }
    notifyListeners();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final service = DiaryNavigationService.instance;
  final target = DateTime(2026, 9, 16);
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
          (_) async => null,
        );
    await ApiService().logout();
    service.consume();
    service.consumeTab();
    service.pendingChat.value = null;
  });

  test('launch links survive initialization, and identical later clicks are delivered', () async {
    final stream = StreamController<Uri>();
    final inbox = AppLinkInbox()..start(stream.stream);
    final link = Uri.parse('reschool://diary?date=2026-09-16&subject=Физика');
    stream.add(link);
    await Future<void>.delayed(Duration.zero);
    final received = <Uri>[];
    inbox.attach(received.add);
    expect(received, [link]);
    stream.add(link);
    await Future<void>.delayed(Duration.zero);
    expect(received, [link, link]);
    await inbox.dispose();
    await stream.close();
  });

  for (final type in ['diary', 'homework', 'grade']) {
    testWidgets(
      '$type survives login and waits longer than 500ms for lesson data',
      (tester) async {
        final nav = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('Login')),
          ),
        );
        nav.currentState!.push(
          MaterialPageRoute(builder: (_) => const Scaffold(body: Text('PIN'))),
        );
        await tester.pumpAndSettle();
        DeepLinkHandler.handle(
          Uri.parse(
            'reschool://$type?date=2026-09-16&subject=Физика&lessonId=42',
          ),
          nav,
        );
        await tester.pumpAndSettle();
        expect(find.text('PIN'), findsOneWidget);
        expect(service.pending.value?.date, target);
        final bells = BellScheduleProvider();
        final vm = DelayedDiary(bells);
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider(create: (_) => SettingsProvider()),
              ChangeNotifierProvider.value(value: bells),
              ChangeNotifierProvider(create: (_) => CustomHomeworkProvider()),
              ChangeNotifierProvider<DiaryViewModel>.value(value: vm),
            ],
            child: const MaterialApp(
              localizationsDelegates: [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              supportedLocales: AppLocalizations.supportedLocales,
              home: DiaryView(),
            ),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 2));
        expect(vm.selectedDate, target);
        expect(service.pending.value, isNotNull);
        expect(find.byType(LessonDetailSheet), findsNothing);
        if (type == 'grade') {
          vm.finish(target, failure: 'offline');
          await tester.pump();
          expect(service.pending.value, isNotNull);
          expect(find.byType(LessonDetailSheet), findsNothing);
          await vm.loadSchedule();
        }
        vm.finish(target);
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(service.pending.value, isNull);
        final sheet = tester.widget<LessonDetailSheet>(
          find.byType(LessonDetailSheet),
        );
        expect(sheet.lesson.id, 42);
        expect(sheet.lessonDate, target);
        expect(sheet.lesson.homework, 'Решить задачу 42');
        await tester.pumpWidget(const SizedBox());
        vm.dispose();
        bells.dispose();
      },
    );
  }

  test(
    'messages keep thread, message cursor and group type until home mounts',
    () {
      DeepLinkHandler.handle(
        Uri.parse('reschool://message?threadId=123&msgNum=456&isGroup=true'),
        GlobalKey<NavigatorState>(),
      );
      expect(service.pendingTab.value, 3);
      expect(service.pendingChat.value?.threadId, 123);
      expect(service.pendingChat.value?.messageNumber, 456);
      expect(service.pendingChat.value?.isGroup, true);
    },
  );

  testWidgets(
    'one message link opens the chat after login and replaces an older chat',
    (tester) async {
      await tester.runAsync(() => ApiService().login('demo', 'J7eVN3wl2dXu'));
      addTearDown(() => ApiService().logout());
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider(create: (_) => SettingsProvider()),
            ChangeNotifierProvider(create: (_) => BellScheduleProvider()),
            ChangeNotifierProvider(create: (_) => WidgetConfigProvider()),
            ChangeNotifierProvider(create: (_) => CustomHomeworkProvider()),
          ],
          child: MaterialApp(
            navigatorKey: nav,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,
            home: const Scaffold(body: Text('Login')),
          ),
        ),
      );
      DeepLinkHandler.handle(
        Uri.parse('reschool://message?threadId=123&msgNum=456&isGroup=true'),
        nav,
      );
      await tester.pump();
      expect(find.text('Login'), findsOneWidget);
      nav.currentState!.pushReplacement(
        MaterialPageRoute(
          settings: const RouteSettings(name: '/home'),
          builder: (_) => const HomeScreen(),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pumpAndSettle();
      final screen = tester.widget<ChatDetailScreen>(
        find.byType(ChatDetailScreen),
      );
      expect(screen.threadId, 123);
      expect(screen.initialMessageNumber, 456);
      expect(screen.isGroup, true);
      expect(service.pendingChat.value, isNull);
      DeepLinkHandler.handle(
        Uri.parse('reschool://message?threadId=789&msgNum=22'),
        nav,
      );
      await tester.pump();
      await tester.pumpAndSettle();
      expect(
        tester.widget<ChatDetailScreen>(find.byType(ChatDetailScreen)).threadId,
        789,
      );
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.byType(ChatDetailScreen), findsNothing);
      expect(find.byType(HomeScreen), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );

  test('a newer destination cancels an old pending lesson or chat', () {
    service.switchTab(0, date: target, subject: 'Физика');
    final old = service.pending.value!;
    service.switchTab(0, date: target, subject: 'Химия');
    service.complete(old);
    expect(service.pending.value?.subject, 'Химия');
    service.openChat(ChatNavigationRequest(threadId: 123));
    expect(service.pending.value, isNull);
    service.switchTab(1);
    expect(service.pendingChat.value, isNull);
  });
}
