import 'dart:io';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:reschool/providers/settings_provider.dart';
import 'package:reschool/providers/grading_provider.dart';
import 'package:reschool/models/cloud_connection.dart';
import 'package:reschool/l10n/app_localizations.dart';
import 'package:reschool/screens/grading_settings_screen.dart';
import 'package:reschool/screens/privacy_policy_screen.dart';
import 'package:reschool/screens/terms_of_use_screen.dart';
import 'package:reschool/screens/pin_setup_screen.dart';
import 'package:reschool/screens/server_updates_screen.dart';
import 'package:reschool/screens/cloud_connection_screen.dart';
import 'package:reschool/screens/cloud_functions_screen.dart';
import 'package:reschool/services/advanced_cloud_service.dart';
import 'package:reschool/utils/app_font.dart';
import 'package:reschool/utils/app_theme.dart';
import 'package:reschool/widgets/homework_rich_text.dart';

const _fontKeys = [
  'inter',
  'rubik',
  'golosText',
  'nunito',
  'manrope',
  'ptSans',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    // берём настоящие байты шрифта из sdk, чтобы тесты не зависели от сети
    final artifacts = File(Platform.resolvedExecutable).parent.parent.parent;
    final font = ByteData.sublistView(
      await File('${artifacts.path}/material_fonts/Roboto-Regular.ttf')
          .readAsBytes(),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (data) async {
          final key = String.fromCharCodes(data!.buffer.asUint8List());
          if (key == 'AssetManifest.bin') {
            return const StandardMessageCodec().encodeMessage({
              for (final family in _fontKeys.map(appFontName))
                for (final weight in [
                  'Regular',
                  'Medium',
                  'SemiBold',
                  'Bold',
                  'ExtraBold',
                ])
                  '${family.replaceAll(' ', '')}-$weight.ttf': [
                    {'asset': '${family.replaceAll(' ', '')}-$weight.ttf'},
                  ],
            });
          }
          return key.endsWith('.ttf') ? font : null;
        });
    GoogleFonts.config.allowRuntimeFetching = false;
    for (final key in _fontKeys) {
      for (final weight in [
        FontWeight.w400,
        FontWeight.w500,
        FontWeight.w600,
        FontWeight.w700,
        FontWeight.w800,
      ]) {
        GoogleFonts.getFont(appFontName(key), fontWeight: weight);
      }
    }
    await GoogleFonts.pendingFonts();
  });

  testWidgets('existing const text follows a changed font', (tester) async {
    SharedPreferences.setMockInitialValues({'font_family': 'rubik'});
    final settings = SettingsProvider();
    await settings.reloadCloudSettings();
    addTearDown(settings.dispose);
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: Consumer<SettingsProvider>(
          builder: (context, settings, _) => MaterialApp(
            builder: (context, child) =>
                AppFontScope(fontKey: settings.fontFamily, child: child!),
            theme: buildAppTheme(
              fontKey: settings.fontFamily,
              accentColor: Colors.blue,
              brightness: Brightness.light,
            ),
            home: const Scaffold(body: _PersistentFontLabel()),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await settings.setFontFamily('nunito');
    await tester.pumpAndSettle();
    final rendered = tester.widget<RichText>(
      find.descendant(
        of: find.byType(_PersistentFontLabel),
        matching: find.byType(RichText),
      ),
    );
    expect(rendered.text.style!.fontFamily, startsWith('Nunito'));
  });

  for (final screen in <Widget>[
    const PrivacyPolicyScreen(),
    const TermsOfUseScreen(),
    const PinSetupScreen(),
    const GradingSettingsScreen(),
    const CloudConnectionScreen(role: CloudRole.admin),
    ServerUpdatesScreen(service: _ServerUpdates()),
  ]) {
    testWidgets(
      '${screen.runtimeType}: every rendered label follows the setting',
      (tester) async {
        SharedPreferences.setMockInitialValues({'font_family': 'rubik'});
        final settings = SettingsProvider();
        final grading = GradingProvider();
        await settings.reloadCloudSettings();
        addTearDown(settings.dispose);
        addTearDown(grading.dispose);
        await tester.binding.setSurfaceSize(const Size(1100, 1000));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.pumpWidget(
          MultiProvider(
            providers: [
              ChangeNotifierProvider.value(value: settings),
              ChangeNotifierProvider.value(value: grading),
            ],
            child: Consumer<SettingsProvider>(
              child: screen,
              builder: (context, settings, child) => MaterialApp(
                builder: (context, child) =>
                    AppFontScope(fontKey: settings.fontFamily, child: child!),
                locale: const Locale('ru'),
                supportedLocales: AppLocalizations.supportedLocales,
                localizationsDelegates: const [
                  AppLocalizations.delegate,
                  GlobalMaterialLocalizations.delegate,
                  GlobalWidgetsLocalizations.delegate,
                  GlobalCupertinoLocalizations.delegate,
                ],
                // локальная тема не должна подменять выбранную настройку
                theme: screen is ServerUpdatesScreen
                    ? ThemeData(brightness: Brightness.dark)
                    : buildAppTheme(
                        fontKey: settings.fontFamily,
                        accentColor: Colors.blue,
                        brightness: Brightness.light,
                      ),
                home: child,
              ),
            ),
          ),
        );
        for (final key in _fontKeys) {
          await settings.setFontFamily(key);
          await tester.pumpAndSettle();
          final family = appFontName(key).replaceAll(' ', '');
          var labels = 0;
          void check(InlineSpan span, TextStyle inherited) {
            final style = inherited.merge(span.style);
            if (span is TextSpan) {
              if (span.text?.trim().isNotEmpty ?? false) {
                // иконка тоже использует RichText внутри
                if (style.fontFamily != 'MaterialIcons' &&
                    style.fontFamily !=
                        'packages/cupertino_icons/CupertinoIcons') {
                  expect(
                    style.fontFamily,
                    startsWith(family),
                    reason: '${screen.runtimeType}: ${span.text}',
                  );
                  labels++;
                }
              }
              for (final child in span.children ?? <InlineSpan>[]) {
                check(child, style);
              }
            }
          }

          for (final rich in tester.widgetList<RichText>(
            find.byType(RichText),
          )) {
            check(rich.text, const TextStyle());
          }
          expect(labels, greaterThanOrEqualTo(2));
          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }

  for (final brightness in Brightness.values) {
    testWidgets('access page and dialogs follow every font: $brightness', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({
        'font_family': 'rubik',
        'cloud_enabled': true,
        'cloud_role': 'admin',
        'cloud_server_url': 'https://school.example',
        'cloud_api_token': 'test-admin-token',
      });
      final settings = SettingsProvider();
      await settings.reloadCloudSettings();
      addTearDown(settings.dispose);
      await tester.binding.setSurfaceSize(const Size(1100, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        ChangeNotifierProvider.value(
          value: settings,
          child: Consumer<SettingsProvider>(
            child: CloudFunctionsScreen(service: _CloudStatus()),
            builder: (context, settings, child) => MaterialApp(
              builder: (context, child) =>
                  AppFontScope(fontKey: settings.fontFamily, child: child!),
              theme: buildAppTheme(
                fontKey: settings.fontFamily,
                accentColor: Colors.blue,
                brightness: brightness,
              ),
              home: child,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Доступ и приглашения'));
      await tester.pumpAndSettle();

      Future<void> checkEveryFont() async {
        for (final key in _fontKeys) {
          await settings.setFontFamily(key);
          await tester.pumpAndSettle();
          final family = appFontName(key).replaceAll(' ', '');
          var labels = 0;
          void check(InlineSpan span, TextStyle inherited) {
            final style = inherited.merge(span.style);
            if (span is! TextSpan) return;
            if ((span.text?.trim().isNotEmpty ?? false) &&
                style.fontFamily != 'MaterialIcons' &&
                style.fontFamily != 'packages/cupertino_icons/CupertinoIcons') {
              expect(style.fontFamily, startsWith(family), reason: span.text);
              labels++;
            }
            for (final child in span.children ?? <InlineSpan>[]) {
              check(child, style);
            }
          }

          for (final text in tester.widgetList<RichText>(find.byType(RichText))) {
            check(text.text, const TextStyle());
          }
          for (final input in tester.widgetList<EditableText>(
            find.byType(EditableText),
          )) {
            expect(input.style.fontFamily, startsWith(family));
          }
          expect(labels, greaterThanOrEqualTo(3));
          expect(tester.takeException(), isNull);
        }
      }

      for (final label in [
        'API ключ',
        'Класс',
        'Создать приглашение',
        'Показать QR администратора',
        'Подключить браузер',
      ]) {
        expect(find.text(label), findsWidgets);
      }
      await checkEveryFont();
      await tester.tap(find.text('Показать токен'));
      await tester.pumpAndSettle();
      expect(find.text('test-admin-token'), findsOneWidget);
      await checkEveryFont();

      await tester.tap(find.text('Показать QR администратора'));
      await tester.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      await checkEveryFont();
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      await http.runWithClient(() async {
        await tester.tap(find.text('Подключить браузер'));
        await tester.pumpAndSettle();
        expect(find.text('Подключение браузера'), findsOneWidget);
        await checkEveryFont();
        await tester.tap(find.text('Закрыть'));
        await tester.pumpAndSettle();
      }, () => MockClient((request) async {
        expect(request.url.path, '/browser-connection');
        return http.Response('{"connectionCode":"test-code"}', 200);
      }));

      await tester.tap(find.text('Создать приглашение'));
      await tester.pumpAndSettle();
      expect(find.text('Скопировать приглашение'), findsOneWidget);
      await checkEveryFont();
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets('admin token uses the selected font and can be revealed and copied', (
    tester,
  ) async {
    const token = 'test-admin-token-0123456789';
    SharedPreferences.setMockInitialValues({
      'font_family': 'nunito',
      'cloud_enabled': true,
      'cloud_role': 'admin',
      'cloud_server_url': 'https://school.example',
      'cloud_api_token': token,
    });
    final settings = SettingsProvider();
    await settings.reloadCloudSettings();
    addTearDown(settings.dispose);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            copied = (call.arguments as Map)['text'] as String;
          }
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });
    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: settings,
        child: MaterialApp(
          theme: buildAppTheme(
            fontKey: settings.fontFamily,
            accentColor: Colors.blue,
            brightness: Brightness.dark,
          ),
          home: CloudFunctionsScreen(service: _CloudStatus()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Доступ и приглашения'));
    await tester.pumpAndSettle();
    expect(find.text(token), findsNothing);

    await tester.tap(find.text('Скопировать токен'));
    await tester.pumpAndSettle();
    expect(copied, token);
    expect(find.text('Токен администратора скопирован'), findsOneWidget);
    expect(find.text(token), findsNothing);

    await tester.tap(find.text('Показать токен'));
    await tester.pumpAndSettle();
    final revealed = tester.widget<EditableText>(find.text(token));
    expect(revealed.style.fontFamily, startsWith('Nunito'));
    await tester.tap(find.text('Скрыть токен'));
    await tester.pumpAndSettle();
    expect(find.text(token), findsNothing);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('cloud_api_token', '');
    await settings.reloadCloudSettings();
    await tester.pumpAndSettle();
    expect(find.text('Токен не сохранён на этом устройстве'), findsOneWidget);
    expect(find.text('Скопировать токен'), findsNothing);

    await prefs.setString('cloud_role', 'user');
    await prefs.setString('cloud_api_token', 'user-token');
    await settings.reloadCloudSettings();
    await tester.pumpAndSettle();
    expect(find.text('Токен администратора'), findsNothing);
    expect(find.text('user-token'), findsNothing);
    expect(find.text('Показать токен'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  for (final brightness in Brightness.values) {
    testWidgets(
      'all settings fonts reach controls, dialogs and HTML: $brightness',
      (tester) async {
        SharedPreferences.setMockInitialValues({'font_family': 'rubik'});
        final settings = SettingsProvider();
        await settings.reloadCloudSettings();
        addTearDown(settings.dispose);
        await tester.pumpWidget(
          ChangeNotifierProvider.value(
            value: settings,
            child: Consumer<SettingsProvider>(
              builder: (context, settings, _) => MaterialApp(
                builder: (context, child) =>
                    AppFontScope(fontKey: settings.fontFamily, child: child!),
                theme: buildAppTheme(
                  fontKey: settings.fontFamily,
                  accentColor: Colors.blue,
                  brightness: brightness,
                ),
                home: Scaffold(
                  appBar: AppBar(title: const Text('Заголовок')),
                  body: Builder(
                    builder: (context) => Column(
                      children: [
                        const Text('Обычный текст'),
                        const TextField(
                          decoration: InputDecoration(labelText: 'Поле ввода'),
                        ),
                        const CupertinoButton(
                          onPressed: null,
                          child: Text('Кнопка iOS'),
                        ),
                        const HomeworkRichText(
                          '<p style="font-family: Arial !important">HTML текст</p>'
                          '<font face="Times New Roman">Старый HTML</font>'
                          '<pre><code style="font: 12px monospace">Код</code></pre>'
                          '<table><tr><td>Таблица</td></tr></table>',
                        ),
                        FilledButton(
                          onPressed: () => showDialog<void>(
                            context: context,
                            builder: (dialogContext) => AlertDialog(
                              title: const Text('Диалог'),
                              content: Text(
                                'Содержимое',
                                style: appFont(
                                  dialogContext,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          child: const Text('Открыть'),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('Открыть'));
        await tester.pumpAndSettle();

        // меняем шрифт при открытом диалоге, существующие маршруты тоже должны обновиться
        for (final key in _fontKeys) {
          await settings.setFontFamily(key);
          await tester.pumpAndSettle();
          final family = appFontName(key).replaceAll(' ', '');
          final theme = Theme.of(tester.element(find.byType(AlertDialog)));
          expect(
            theme.primaryTextTheme.titleLarge!.fontFamily,
            startsWith(family),
          );
          final richTexts = tester.widgetList<RichText>(
            find.byType(RichText, skipOffstage: false),
          );
          for (final label in [
            'Заголовок',
            'Обычный текст',
            'Поле ввода',
            'Кнопка iOS',
            'HTML текст',
            'Старый HTML',
            'Код',
            'Таблица',
            'Открыть',
            'Диалог',
            'Содержимое',
          ]) {
            final matches = richTexts.where(
              (w) => w.text.toPlainText().trim() == label,
            );
            expect(matches, isNotEmpty, reason: label);
            for (final widget in matches) {
              void check(InlineSpan span, TextStyle inherited) {
                final style = inherited.merge(span.style);
                if (span is TextSpan) {
                  if (span.text?.trim().isNotEmpty ?? false) {
                    expect(
                      style.fontFamily,
                      startsWith(family),
                      reason: '$key: $label',
                    );
                  }
                  for (final child in span.children ?? <InlineSpan>[]) {
                    check(child, style);
                  }
                }
              }

              check(widget.text, const TextStyle());
            }
          }
          expect(
            tester
                .widget<EditableText>(
                  find.byType(EditableText, skipOffstage: false),
                )
                .style
                .fontFamily,
            startsWith(family),
          );

          expect(tester.takeException(), isNull);
        }
        await tester.pumpWidget(const SizedBox.shrink());
      },
    );
  }
}

class _PersistentFontLabel extends StatelessWidget {
  const _PersistentFontLabel();
  @override
  Widget build(BuildContext context) =>
      Text('Надпись', style: appFont(context, fontSize: 16));
}

class _ServerUpdates extends AdvancedCloudService {
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const {},
    String? serverUrl,
    String? token,
    bool public = false,
    bool get = false,
  }) async => {
    'currentVersion': '2.0.0',
    'checkedAt': 123,
    'supported': true,
    'updateAvailable': false,
  };
}

class _CloudStatus extends AdvancedCloudService {
  @override
  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic> body = const {},
    String? serverUrl,
    String? token,
    bool public = false,
    bool get = false,
  }) async => {
    'role': 'admin',
    'gradeClass': '9А',
    'monitoring': false,
    if (path == '/cloud/invites') 'inviteToken': 'test-invite',
  };
}
