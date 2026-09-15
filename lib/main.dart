import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'services/secure_storage.dart';
import 'utils/app_theme.dart';
import 'utils/app_font.dart';

import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:app_links/app_links.dart';

import 'l10n/app_localizations.dart';
import 'providers/theme_provider.dart';
import 'providers/settings_provider.dart';
import 'providers/bell_schedule_provider.dart';
import 'providers/widget_config_provider.dart';
import 'providers/grading_provider.dart';
import 'providers/custom_homework_provider.dart';
import 'screens/login_screen.dart';
import 'viewmodels/assignments_viewmodel.dart';
import 'services/widget_data_service.dart';
import 'services/marks_cache_service.dart';
import 'services/api_service.dart';
import 'services/deep_link_handler.dart';
import 'services/windows_protocol_service.dart';
import 'services/linux_protocol_service.dart';
import 'services/tls_pin_store.dart';
import 'services/app_link_inbox.dart';

final _appLinks = AppLinkInbox();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // сохраняем ссылки, чтобы не потерять переходы во время запуска
  _appLinks.start(AppLinks().uriLinkStream);

  try {
    await appSecureStorage.delete(key: 'fcm_token');
  } catch (_) {
    // ошибка локального хранилища не должна мешать запуску дневника
  }

  // пины сертификатов нужны раньше первого запроса к своему серверу
  await TlsPinStore.instance.load();

  if (!kIsWeb) {
    // виджеты домашнего экрана
    await WidgetDataService().initialize();

    // схема reschool:// в реестре windows
    await WindowsProtocolService.registerIfNeeded();
    await LinuxProtocolService.registerIfNeeded();

    // на телефонах фиксируем портрет, планшеты крутятся свободно
    final view = WidgetsBinding.instance.platformDispatcher.views.first;
    final shortestSide = view.physicalSize.shortestSide / view.devicePixelRatio;
    if (shortestSide < 600) {
      await SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]);
    }
  }

  // старые оценки без владельца нельзя переносить в кеш нового аккаунта
  await MarksCacheService().migrateLegacyData();

  runApp(const ReSchoolApp());
}

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class ReSchoolApp extends StatefulWidget {
  const ReSchoolApp({super.key});

  @override
  State<ReSchoolApp> createState() => _ReSchoolAppState();
}

class _ReSchoolAppState extends State<ReSchoolApp> {
  @override
  void initState() {
    super.initState();
    _initDeepLinks();
  }

  void _initDeepLinks() {
    _appLinks.start(AppLinks().uriLinkStream);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _appLinks.attach((uri) => DeepLinkHandler.handle(uri, navigatorKey));
    });
  }

  @override
  void dispose() {
    _appLinks.detach();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => SettingsProvider()),
        ChangeNotifierProvider(create: (_) => BellScheduleProvider()),
        ChangeNotifierProvider(create: (_) => WidgetConfigProvider()),
        ChangeNotifierProvider(create: (_) => GradingProvider()),
        ChangeNotifierProvider(create: (_) => CustomHomeworkProvider()),
        ChangeNotifierProvider(
          create: (context) => AssignmentsViewModel(
            Provider.of<SettingsProvider>(context, listen: false),
          ),
        ),
      ],
      child: Consumer2<ThemeProvider, SettingsProvider>(
        builder: (context, themeProvider, settingsProvider, child) {
          // прокси нужно переставлять при каждом изменении настроек
          if (kIsWeb && settingsProvider.isLoaded) {
            ApiService().setWebProxy(
              settingsProvider.webProxyServerUrl,
              settingsProvider.webProxyToken,
            );
          }
          return MaterialApp(
            // единый размер текста на всех экранах, включая маршруты и диалоги
            builder: (context, child) => MediaQuery.withNoTextScaling(
              child: AppFontScope(
                fontKey: settingsProvider.fontFamily,
                child: child!,
              ),
            ),
            navigatorKey: navigatorKey,
            title: 'reSchool',
            debugShowCheckedModeBanner: false,

            locale: settingsProvider.locale,
            localizationsDelegates: const [
              AppLocalizations.delegate,
              GlobalMaterialLocalizations.delegate,
              GlobalWidgetsLocalizations.delegate,
              GlobalCupertinoLocalizations.delegate,
            ],
            supportedLocales: AppLocalizations.supportedLocales,

            themeMode: themeProvider.themeMode,

            theme: buildAppTheme(
              fontKey: settingsProvider.fontFamily,
              accentColor: themeProvider.accentColor,
              brightness: Brightness.light,
            ),
            darkTheme: buildAppTheme(
              fontKey: settingsProvider.fontFamily,
              accentColor: themeProvider.accentColor,
              brightness: Brightness.dark,
            ),

            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}
