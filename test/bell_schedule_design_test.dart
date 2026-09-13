import 'dart:io';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:reschool/l10n/app_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reschool/services/bell_time_service.dart';
import 'package:reschool/screens/bell_schedule_screen.dart';
import 'package:reschool/providers/bell_schedule_provider.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final fonts = <String, ByteData>{};
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final fallback = await File(
      '${artifacts.path}/material_fonts/Roboto-Regular.ttf',
    ).readAsBytes();
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      fonts[weight] = ByteData.sublistView(fallback);
    }
    // для необязательного превью берём шрифт из локального кеша
    final cache = Directory(
      '${Platform.environment['HOME']}/.local/share/com.example.reschool',
    );
    if (cache.existsSync()) {
      for (final entry in cache.listSync().whereType<File>()) {
        for (final weight in {
          'regular': 'Regular',
          '500': 'Medium',
          '600': 'SemiBold',
          '700': 'Bold',
        }.entries) {
          if (entry.path.split('/').last.startsWith('Inter_${weight.key}_')) {
            fonts[weight.value] = ByteData.sublistView(
              await entry.readAsBytes(),
            );
          }
        }
      }
    }
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            await File(
              '${artifacts.path}/material_fonts/MaterialIcons-Regular.otf',
            ).readAsBytes(),
          ),
        ),
      );
    await icons.load();
    final regular = FontLoader('ProfilePreview')
      ..addFont(Future.value(fonts['Regular']!));
    await regular.load();
  });
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (data) async {
          final key = String.fromCharCodes(data!.buffer.asUint8List());
          if (key == 'AssetManifest.bin') {
            return const StandardMessageCodec().encodeMessage({
              for (final weight in fonts.keys)
                'Inter-$weight.ttf': [
                  {'asset': 'Inter-$weight.ttf'},
                ],
            });
          }
          for (final weight in fonts.keys) {
            if (key == 'Inter-$weight.ttf') return fonts[weight];
          }
          return null;
        });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  for (final config in [
    (const Size(1024, 850), Brightness.dark, 1.0),
    (const Size(1024, 850), Brightness.light, 1.0),
    (const Size(390, 844), Brightness.dark, 1.0),
    (const Size(320, 740), Brightness.dark, 2.0),
    (const Size(1024, 420), Brightness.dark, 1.0),
  ]) {
    testWidgets('bells ${config.$1} ${config.$2.name} scale ${config.$3}', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      tester.view.physicalSize = config.$1;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final provider = BellScheduleProvider(
        startTimers: false,
        bellTimeService: BellTimeService(
          client: MockClient(
            (_) async => http.Response(
              jsonEncode({
                'version': 1,
                'timezone': 'Europe/Moscow',
                'serverTimeMs': DateTime.now().millisecondsSinceEpoch,
                'presets': {
                  for (final id in BellTimeService.campusIds)
                    id: {
                      'offsetSeconds': 126,
                      'lessons': {
                        '1': {'start': '08:50', 'end': '09:35'},
                      },
                    },
                },
              }),
              200,
            ),
          ),
        ),
      );
      addTearDown(provider.dispose);
      final boundary = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: boundary,
          child: ChangeNotifierProvider.value(
            value: provider,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: ThemeData(
                useMaterial3: true,
                fontFamily: 'ProfilePreview',
                colorScheme: ColorScheme.fromSeed(
                  seedColor: const Color(0xFF6A11CB),
                  brightness: config.$2,
                ),
              ),
              locale: const Locale('ru'),
              supportedLocales: AppLocalizations.supportedLocales,
              localizationsDelegates: const [
                AppLocalizations.delegate,
                GlobalMaterialLocalizations.delegate,
                GlobalWidgetsLocalizations.delegate,
                GlobalCupertinoLocalizations.delegate,
              ],
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context)
                    .copyWith(textScaler: TextScaler.linear(config.$3)),
                child: child!,
              ),
              home: const BellScheduleScreen(),
            ),
          ),
        ),
      );
      await tester.runAsync(() async {
        await GoogleFonts.pendingFonts();
      });
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('09:00 - 09:45'), findsOneWidget);
      if (config.$1.height == 850 &&
          const bool.fromEnvironment('BELL_PREVIEW')) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/bell_preview/${config.$2.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('+10 сек'));
      await tester.tap(find.text('+10 сек'));
      await tester.pumpAndSettle();
      expect(provider.timeOffset, 10);
      await tester.ensureVisible(find.byType(Switch));
      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();
      expect(provider.autoScheduleEnabled, isTrue);
      expect(find.text('Пн'), findsOneWidget);
      expect(find.text('Сб'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await provider.setAutoScheduleEnabled(false);
      await provider.applyPreset('fml30_shevchenko');
      await tester.pumpAndSettle();
      expect(provider.usesServerTime, isTrue);
      expect(find.text('08:52:06 - 09:37:06'), findsOneWidget);
      expect(find.text('С сервера'), findsOneWidget);
      expect(tester.takeException(), isNull);
      if (config.$1.height == 850 &&
          const bool.fromEnvironment('BELL_PREVIEW')) {
        await tester.runAsync(() async {
          final render =
              boundary.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary;
          final image = await render.toImage();
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          final file = File('build/bell_preview/server_${config.$2.name}.png');
          await file.parent.create(recursive: true);
          await file.writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      await tester.ensureVisible(find.text('Вручную'));
      await tester.tap(find.text('Вручную'));
      await tester.pumpAndSettle();
      expect(provider.usesServerTime, isFalse);
      expect(provider.timeOffset, 0);
      expect(tester.takeException(), isNull);
    });
  }
}
