import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await WidgetDataService().initialize();

  runApp(const ReSchoolApp());
}

class ReSchoolApp extends StatelessWidget {
  const ReSchoolApp({super.key});

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
          return MaterialApp(
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

            theme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.light,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6A11CB),
                brightness: Brightness.light,
              ),
              textTheme: GoogleFonts.interTextTheme(ThemeData.light().textTheme),
              scaffoldBackgroundColor: const Color(0xFFF5F5F7),
            ),

            darkTheme: ThemeData(
              useMaterial3: true,
              brightness: Brightness.dark,
              colorScheme: ColorScheme.fromSeed(
                seedColor: const Color(0xFF6A11CB),
                brightness: Brightness.dark,
              ),
              textTheme: GoogleFonts.interTextTheme(ThemeData.dark().textTheme),
              scaffoldBackgroundColor: const Color(0xFF121212),
            ),

            home: const LoginScreen(),
          );
        },
      ),
    );
  }
}