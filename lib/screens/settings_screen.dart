import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, kDebugMode;
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../l10n/app_localizations.dart';
import '../providers/theme_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/bell_schedule_provider.dart';
import '../providers/widget_config_provider.dart';
import '../services/api_service.dart';
import '../services/browser_server.dart';
import '../services/widget_data_service.dart';
import '../services/widget_sync_service.dart';
import '../services/update_service.dart';
import '../widgets/app_card.dart';
import 'pin_setup_screen.dart';
import '../services/pin_service.dart';
import '../utils/app_font.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with TickerProviderStateMixin {
  final ApiService _api = ApiService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late TabController _tabController;

  int _devModeTapCount = 0;
  Timer? _devModeTapResetTimer;

  static const int _tabCount = 4;

  // состояние пин кода и биометрии
  bool _isPinEnabled = false;
  bool _isBiometricsEnabled = false;
  bool _isBiometricsAvailable = false;
  final _pinService = PinService();

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabCount, vsync: this);
    _setupAnimations();
    _loadPinState();
  }

  Future<void> _loadPinState() async {
    final pinEnabled = await _pinService.isPinEnabled();
    final bioEnabled = await _pinService.isBiometricsEnabled();
    final bioAvailable = await _pinService.isBiometricsAvailable();
    if (mounted) {
      setState(() {
        _isPinEnabled = pinEnabled;
        _isBiometricsEnabled = bioEnabled;
        _isBiometricsAvailable = bioAvailable;
      });
    }
  }

  void _setupAnimations() {
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _animationController.dispose();
    _devModeTapResetTimer?.cancel();
    super.dispose();
  }

  Future<void> _showLanguageDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.selectLanguage,
          style: appFont(context, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text("Русский", style: appFont(context)),
              trailing: settings.locale.languageCode == 'ru'
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () {
                settings.setLocale(const Locale('ru'));
                Navigator.pop(context);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            ListTile(
              title: Text("English", style: appFont(context)),
              trailing: settings.locale.languageCode == 'en'
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () {
                settings.setLocale(const Locale('en'));
                Navigator.pop(context);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(l10n.cancel, style: appFont(context)),
          ),
        ],
      ),
    );
  }

  Future<void> _showDiaryInitialDayDialog(
    BuildContext context,
    SettingsProvider settings,
  ) async {
    final colorScheme = Theme.of(context).colorScheme;

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Открывать в дневнике',
          style: appFont(context, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('Сегодня', style: appFont(context)),
              trailing: settings.diaryInitialDay == 'today'
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () {
                settings.setDiaryInitialDay('today');
                Navigator.pop(context);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            ListTile(
              title: Text('Завтра', style: appFont(context)),
              trailing: settings.diaryInitialDay == 'tomorrow'
                  ? Icon(Icons.check_rounded, color: colorScheme.primary)
                  : null,
              onTap: () {
                settings.setDiaryInitialDay('tomorrow');
                Navigator.pop(context);
              },
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Отмена', style: appFont(context)),
          ),
        ],
      ),
    );
  }

  Future<int?> _showNumberInputDialog(
    BuildContext context,
    String title,
    int initialValue,
  ) async {
    final controller = TextEditingController(text: initialValue.toString());
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return showDialog<int>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(title, style: appFont(context, fontWeight: FontWeight.w600)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.of(context).viewInsets.bottom > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
                        .withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                      ),
                    ],
                  ),
                  child: IconButton(
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                    onPressed: _dismissKeyboard,
                  ),
                ),
              ),
            TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.done,
              onEditingComplete: _dismissKeyboard,
              autofocus: true,
              style: appFont(context, fontSize: 16),
              decoration: InputDecoration(
                labelText: l10n.numberOfDays,
                labelStyle: appFont(context,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outline.withValues(alpha: 0.2),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.primary, width: 2),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              l10n.cancel,
              style: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              final value = int.tryParse(controller.text);
              Navigator.pop(context, value);
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(l10n.save, style: appFont(context, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: appFont(context)),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final settingsProvider = Provider.of<SettingsProvider>(context);
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    final tabItems = [
      (icon: Icons.tune_rounded, label: l10n.general),
      (icon: Icons.upload_file_rounded, label: 'Экспорт'),
      (icon: Icons.palette_outlined, label: l10n.appearance),
      (icon: Icons.info_outline_rounded, label: l10n.aboutApp),
    ];

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            l10n.settings,
            style: appFont(context,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        body: FadeTransition(
          opacity: _fadeAnimation,
          child: Column(
            children: [
              // свой переключатель вкладок в виде пилюль
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: AnimatedBuilder(
                  animation: _tabController,
                  builder: (context, _) {
                    return Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: colorScheme.onSurface.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      padding: const EdgeInsets.all(4),
                      child: Row(
                        children: List.generate(tabItems.length, (i) {
                          final selected = _tabController.index == i;
                          final item = tabItems[i];
                          return Expanded(
                            child: GestureDetector(
                              onTap: () => _tabController.animateTo(i),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                curve: Curves.easeInOut,
                                decoration: BoxDecoration(
                                  color: selected
                                      ? colorScheme.surface
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    AnimatedScale(
                                      scale: selected ? 1.1 : 1.0,
                                      duration: const Duration(
                                        milliseconds: 200,
                                      ),
                                      child: Icon(
                                        item.icon,
                                        size: 18,
                                        color: selected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface.withValues(
                                                alpha: 0.45,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      item.label,
                                      style: appFont(context,
                                        fontSize: 10,
                                        fontWeight: selected
                                            ? FontWeight.w600
                                            : FontWeight.w400,
                                        color: selected
                                            ? colorScheme.primary
                                            : colorScheme.onSurface.withValues(
                                                alpha: 0.45,
                                              ),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        }),
                      ),
                    );
                  },
                ),
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    _buildTabGeneral(
                      themeProvider,
                      settingsProvider,
                      colorScheme,
                      l10n,
                    ),
                    _buildTabExport(settingsProvider, colorScheme, l10n),
                    _buildTabAppearance(
                      themeProvider,
                      settingsProvider,
                      colorScheme,
                      l10n,
                    ),
                    _buildTabAbout(settingsProvider, colorScheme, l10n),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTabGeneral(
    ThemeProvider themeProvider,
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SingleChildScrollView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader(l10n.general, colorScheme),
          const SizedBox(height: 12),
          _buildGeneralCard(settingsProvider, colorScheme, l10n),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.homework, colorScheme),
          const SizedBox(height: 12),
          _buildHomeworkCard(settingsProvider, colorScheme, l10n),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.emulation, colorScheme),
          const SizedBox(height: 12),
          _buildEmulationCard(colorScheme, l10n),
          const SizedBox(height: 24),
          _buildSectionHeader(l10n.security, colorScheme),
          const SizedBox(height: 12),
          _buildSecurityCard(colorScheme, l10n),
          if (kIsWeb) ...[
            const SizedBox(height: 24),
            _buildSectionHeader('Веб-прокси', colorScheme),
            const SizedBox(height: 12),
            _buildWebProxySection(settingsProvider, colorScheme),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildTabExport(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader('Obsidian', colorScheme),
          const SizedBox(height: 12),
          _buildObsidianCard(settingsProvider, colorScheme),
          if (WidgetDataService().isSupported) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(l10n.widgets, colorScheme),
            const SizedBox(height: 12),
            _buildWidgetSettingsSection(context, colorScheme, l10n),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildTabAppearance(
    ThemeProvider themeProvider,
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader(l10n.appearance, colorScheme),
          const SizedBox(height: 12),
          _buildThemeSelector(themeProvider, colorScheme, l10n),
          const SizedBox(height: 24),
          _buildSectionHeader('Цветовая тема', colorScheme),
          const SizedBox(height: 12),
          _buildColorThemeSelector(themeProvider, colorScheme),
          const SizedBox(height: 24),
          _buildSectionHeader('Шрифт', colorScheme),
          const SizedBox(height: 12),
          _buildFontSelector(settingsProvider, colorScheme),
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  static const _fonts = [
    (key: 'inter', name: 'Inter', desc: 'Стандартный'),
    (key: 'rubik', name: 'Rubik', desc: 'Округлый'),
    (key: 'golosText', name: 'Golos Text', desc: 'Кириллица'),
    (key: 'nunito', name: 'Nunito', desc: 'Дружелюбный'),
    (key: 'manrope', name: 'Manrope', desc: 'Геометрический'),
    (key: 'ptSans', name: 'PT Sans', desc: 'Классический'),
  ];

  Widget _buildFontSelector(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
  ) {
    return SizedBox(
      height: 90,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _fonts.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final font = _fonts[i];
          final isSelected = settingsProvider.fontFamily == font.key;
          return GestureDetector(
            onTap: () => settingsProvider.setFontFamily(font.key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 110,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primaryContainer
                    : colorScheme.surfaceContainerHighest.withValues(
                        alpha: 0.5,
                      ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? colorScheme.primary : Colors.transparent,
                  width: 2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    'Аб',
                    style: _fontPreviewStyle(font.key).copyWith(
                      fontSize: 22,
                      fontWeight: FontWeight.w700,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    font.name,
                    style: appFont(context, 
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onPrimaryContainer
                          : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    font.desc,
                    style: appFont(context, 
                      fontSize: 10,
                      color:
                          (isSelected
                                  ? colorScheme.onPrimaryContainer
                                  : colorScheme.onSurface)
                              .withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildColorThemeSelector(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
  ) {
    final themes = ThemeProvider.colorThemes;
    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: themes.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          final theme = themes[i];
          final isSelected = themeProvider.colorThemeId == theme.id;
          return GestureDetector(
            onTap: () => themeProvider.setColorTheme(theme.id),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 72,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest.withValues(
                  alpha: 0.5,
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isSelected ? theme.seed : Colors.transparent,
                  width: 2.5,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: isSelected ? 44 : 38,
                    height: isSelected ? 44 : 38,
                    decoration: BoxDecoration(
                      color: theme.seed,
                      shape: BoxShape.circle,
                    ),
                    child: isSelected
                        ? const Icon(
                            Icons.check_rounded,
                            color: Colors.white,
                            size: 20,
                          )
                        : null,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    theme.name,
                    style: appFont(context, 
                      fontSize: 10,
                      fontWeight: isSelected
                          ? FontWeight.w700
                          : FontWeight.w500,
                      color: isSelected
                          ? theme.seed
                          : colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  TextStyle _fontPreviewStyle(String key) {
    switch (key) {
      case 'rubik':
        return GoogleFonts.rubik();
      case 'golosText':
        return GoogleFonts.golosText();
      case 'nunito':
        return GoogleFonts.nunito();
      case 'manrope':
        return GoogleFonts.manrope();
      case 'ptSans':
        return GoogleFonts.ptSans();
      default:
        return GoogleFonts.inter();
    }
  }

  Widget _buildTabAbout(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 20),
          _buildSectionHeader(l10n.aboutApp, colorScheme),
          const SizedBox(height: 12),
          _buildAboutCard(settingsProvider, colorScheme, l10n),
          if (settingsProvider.developerMode) ...[
            const SizedBox(height: 24),
            _buildSectionHeader(l10n.developer, colorScheme),
            const SizedBox(height: 12),
            _buildDeveloperCard(settingsProvider, colorScheme, l10n),
          ],
          const SizedBox(height: 48),
        ],
      ),
    );
  }

  Widget _buildGeneralCard(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        _SettingsRow(
          icon: Icons.language_rounded,
          title: l10n.language,
          subtitle: settingsProvider.locale.languageCode == 'ru'
              ? 'Русский'
              : 'English',
          onTap: () => _showLanguageDialog(context, settingsProvider),
          colorScheme: colorScheme,
        ),
        _SettingsDivider(colorScheme: colorScheme),
        _SettingsSwitch(
          icon: Icons.calendar_today_rounded,
          title: l10n.onlyCurrentYear,
          subtitle: l10n.hideOldDiaries,
          value: settingsProvider.displayOnlyCurrentClass,
          onChanged: (v) => settingsProvider.setDisplayOnlyCurrentClass(v),
          colorScheme: colorScheme,
        ),
        _SettingsDivider(colorScheme: colorScheme),
        _SettingsSwitch(
          icon: Icons.chat_bubble_outline_rounded,
          title: 'Написать учителю',
          subtitle: 'Иконка чата рядом с именем учителя в дневнике и оценках',
          value: settingsProvider.teacherChatEnabled,
          onChanged: (v) => settingsProvider.setTeacherChatEnabled(v),
          colorScheme: colorScheme,
        ),
        _SettingsDivider(colorScheme: colorScheme),
        _SettingsRow(
          icon: Icons.today_rounded,
          title: 'Открывать в дневнике',
          subtitle: settingsProvider.diaryInitialDay == 'tomorrow'
              ? 'Завтра'
              : 'Сегодня',
          onTap: () => _showDiaryInitialDayDialog(context, settingsProvider),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildHomeworkCard(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        _SettingsRow(
          icon: Icons.history_rounded,
          title: l10n.daysInPast,
          subtitle: "${settingsProvider.hwDaysPast} д.",
          onTap: () async {
            final newValue = await _showNumberInputDialog(
              context,
              l10n.daysInPast,
              settingsProvider.hwDaysPast,
            );
            if (newValue != null && newValue >= 0) {
              settingsProvider.setHwDaysPast(newValue);
            }
          },
          colorScheme: colorScheme,
        ),
        _SettingsDivider(colorScheme: colorScheme),
        _SettingsRow(
          icon: Icons.update_rounded,
          title: l10n.daysInFuture,
          subtitle: "${settingsProvider.hwDaysFuture} д.",
          onTap: () async {
            final newValue = await _showNumberInputDialog(
              context,
              l10n.daysInFuture,
              settingsProvider.hwDaysFuture,
            );
            if (newValue != null && newValue >= 0) {
              settingsProvider.setHwDaysFuture(newValue);
            }
          },
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildObsidianCard(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
  ) {
    final enabled = settingsProvider.obsidianEnabled;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _SettingsSwitch(
              icon: Icons.auto_stories_outlined,
              title: 'Экспорт в Obsidian',
              subtitle: 'Добавляет кнопку экспорта в дневнике',
              value: enabled,
              onChanged: (v) => settingsProvider.setObsidianEnabled(v),
              colorScheme: colorScheme,
            ),
          ],
        ),
        AnimatedSize(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          child: enabled
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 16),
                    _buildObsidianGuideCard(colorScheme),
                    const SizedBox(height: 16),
                    _SettingsCard(
                      colorScheme: colorScheme,
                      children: [
                        _SettingsRow(
                          icon: Icons.folder_copy_outlined,
                          title: 'Папка для экспорта',
                          subtitle:
                              settingsProvider.obsidianOutputDir?.isNotEmpty ==
                                  true
                              ? settingsProvider.obsidianOutputDir!
                              : 'Не задана (будет использован kmi-paste)',
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (settingsProvider.obsidianOutputDir != null)
                                GestureDetector(
                                  onTap: () => settingsProvider
                                      .setObsidianOutputDir(null),
                                  child: Icon(
                                    Icons.close_rounded,
                                    size: 18,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                ),
                              const SizedBox(width: 8),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 14,
                                color: colorScheme.onSurface.withValues(
                                  alpha: 0.3,
                                ),
                              ),
                            ],
                          ),
                          onTap: () async {
                            final result = await FilePicker.getDirectoryPath(
                              dialogTitle:
                                  'Выберите папку для экспорта .md файлов',
                            );
                            if (result != null) {
                              await settingsProvider.setObsidianOutputDir(
                                result,
                              );
                            }
                          },
                          colorScheme: colorScheme,
                        ),
                        _SettingsSwitch(
                          icon: Icons.grade_outlined,
                          title: 'Показывать оценки',
                          subtitle: 'Включать оценки в экспортируемый .md файл',
                          value: settingsProvider.obsidianShowMarks,
                          onChanged: (v) =>
                              settingsProvider.setObsidianShowMarks(v),
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SettingsCard(
                      colorScheme: colorScheme,
                      children: [
                        _SettingsRow(
                          icon: Icons.inventory_2_outlined,
                          title: 'Название хранилища',
                          subtitle:
                              settingsProvider.obsidianVault?.isNotEmpty == true
                              ? settingsProvider.obsidianVault!
                              : 'Не задано (выберется автоматически)',
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          onTap: () => _showObsidianVaultDialog(
                            settingsProvider,
                            colorScheme,
                          ),
                          colorScheme: colorScheme,
                        ),
                        _SettingsRow(
                          icon: Icons.folder_open_outlined,
                          title: 'Папка в хранилище',
                          subtitle:
                              settingsProvider.obsidianPath?.isNotEmpty == true
                              ? settingsProvider.obsidianPath!
                              : 'Корень хранилища',
                          trailing: Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 14,
                            color: colorScheme.onSurface.withValues(alpha: 0.3),
                          ),
                          onTap: () => _showObsidianPathDialog(
                            settingsProvider,
                            colorScheme,
                          ),
                          colorScheme: colorScheme,
                        ),
                      ],
                    ),
                  ],
                )
              : const SizedBox.shrink(),
        ),
      ],
    );
  }

  Widget _buildObsidianGuideCard(ColorScheme colorScheme) {
    const steps = [
      (
        num: '1',
        icon: Icons.install_mobile_outlined,
        title: 'Установите Obsidian',
        subtitle:
            'Скачайте и установите приложение Obsidian на ваше устройство.',
        url: 'https://obsidian.md/download',
        urlLabel: 'obsidian.md/download',
        copyLabel: null,
      ),
      (
        num: '2',
        icon: Icons.extension_outlined,
        title: 'Установите плагин BRAT',
        subtitle:
            'Настройки → Сторонние плагины → Просмотр → «BRAT» → Установить.',
        url: null,
        urlLabel: null,
        copyLabel: null,
      ),
      (
        num: '3',
        icon: Icons.add_link_rounded,
        title: 'Добавьте kmi-paste через BRAT',
        subtitle: 'В настройках BRAT нажмите «Add Beta Plugin» и введите:',
        url: null,
        urlLabel: null,
        copyLabel: 'magiskyp/kmi-paste',
      ),
      (
        num: '4',
        icon: Icons.toggle_on_outlined,
        title: 'Включите плагин',
        subtitle:
            'После установки включите kmi-paste в списке сторонних плагинов.',
        url: null,
        urlLabel: null,
        copyLabel: null,
      ),
    ];

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.15)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                'Как установить',
                style: appFont(context,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...steps.map(
            (step) => Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        step.num,
                        style: appFont(context,
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style: appFont(context,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.subtitle,
                          style: appFont(context,
                            fontSize: 12,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                            height: 1.4,
                          ),
                        ),
                        if (step.url != null) ...[
                          const SizedBox(height: 6),
                          _ObsidianChip(
                            label: step.urlLabel!,
                            icon: Icons.open_in_new_rounded,
                            colorScheme: colorScheme,
                            onTap: () => launchUrl(
                              Uri.parse(step.url!),
                              mode: LaunchMode.externalApplication,
                            ),
                          ),
                        ],
                        if (step.copyLabel != null) ...[
                          const SizedBox(height: 6),
                          _ObsidianChip(
                            label: step.copyLabel!,
                            icon: Icons.copy_rounded,
                            colorScheme: colorScheme,
                            onTap: () {
                              Clipboard.setData(
                                ClipboardData(text: step.copyLabel!),
                              );
                              _showSnackBar('Скопировано: ${step.copyLabel}');
                            },
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showObsidianVaultDialog(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => _ObsidianVaultDialog(
        settingsProvider: settingsProvider,
        colorScheme: colorScheme,
      ),
    );
  }

  Future<void> _showObsidianPathDialog(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
  ) async {
    await showDialog(
      context: context,
      builder: (dialogContext) => _ObsidianPathDialog(
        settingsProvider: settingsProvider,
        colorScheme: colorScheme,
      ),
    );
  }

  Widget _buildEmulationCard(ColorScheme colorScheme, AppLocalizations l10n) {
    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        _SettingsRow(
          icon: Icons.smartphone_rounded,
          title: _api.deviceModel,
          subtitle: l10n.usedForLogin,
          trailing: IconButton(
            icon: Icon(
              Icons.shuffle_rounded,
              size: 20,
              color: colorScheme.primary,
            ),
            onPressed: () async {
              HapticFeedback.lightImpact();
              await _api.randomizeDeviceModel();
              setState(() {});
              if (mounted) {
                _showSnackBar("Device: ${_api.deviceModel}");
              }
            },
          ),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildSecurityCard(ColorScheme colorScheme, AppLocalizations l10n) {
    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        // переключатель пин кода
        _SettingsSwitch(
          icon: Icons.pin_outlined,
          title: l10n.pinCode,
          subtitle: _isPinEnabled ? l10n.pinCodeEnabled : l10n.pinCodeDisabled,
          value: _isPinEnabled,
          onChanged: (value) async {
            if (value) {
              // включаем пин, уводим на экран создания
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const PinSetupScreen()),
              );
              if (result == true) {
                await _loadPinState();
                if (mounted) _showSnackBar(l10n.pinCodeEnabled);
              }
            } else {
              // выключаем пин, но сначала переспрашиваем
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  title: Text(
                    l10n.disablePinQuestion,
                    style: appFont(ctx, fontWeight: FontWeight.w600),
                  ),
                  content: Text(l10n.disablePinWarning, style: appFont(ctx)),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx, false),
                      child: Text(l10n.cancel, style: appFont(ctx)),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(ctx, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: colorScheme.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: Text(l10n.disable, style: appFont(ctx)),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await _pinService.removePin();
                await _loadPinState();
              }
            }
          },
          colorScheme: colorScheme,
        ),
        // смена пина доступна, только когда он включён
        if (_isPinEnabled) ...[
          _SettingsDivider(colorScheme: colorScheme),
          _SettingsRow(
            icon: Icons.edit_outlined,
            title: l10n.changePin,
            onTap: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const PinSetupScreen()),
              );
              if (result == true) {
                await _loadPinState();
                if (mounted) _showSnackBar(l10n.pinCodeEnabled);
              }
            },
            colorScheme: colorScheme,
          ),
        ],
        // биометрия: нужен и включённый пин, и поддержка на устройстве
        if (_isPinEnabled && _isBiometricsAvailable) ...[
          _SettingsDivider(colorScheme: colorScheme),
          _SettingsSwitch(
            icon: Icons.fingerprint_rounded,
            title: l10n.biometrics,
            subtitle: l10n.biometricsSubtitle,
            value: _isBiometricsEnabled,
            onChanged: (value) async {
              await _pinService.setBiometricsEnabled(value);
              await _loadPinState();
            },
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }

  Widget _buildAboutCard(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        _SettingsRow(
          icon: Icons.info_outline_rounded,
          title: l10n.version,
          onTap: () async {
            // скрытый вход в режим разработчика, в интерфейсе его нет, пока не включишь
            if (!kDebugMode) return;
            if (settingsProvider.developerMode) return;

            _devModeTapResetTimer?.cancel();
            _devModeTapCount++;
            _devModeTapResetTimer = Timer(const Duration(seconds: 2), () {
              _devModeTapCount = 0;
            });

            if (_devModeTapCount >= 7) {
              _devModeTapCount = 0;
              HapticFeedback.heavyImpact();
              await settingsProvider.setDeveloperMode(true);
              if (mounted) {
                _showSnackBar(l10n.developerModeEnabled);
              }
            }
          },
          trailing: FutureBuilder<String>(
            future: UpdateService.currentVersion,
            builder: (context, snapshot) {
              final appVer = snapshot.data ?? '...';
              final eschoolVer = _api.eSchoolVersion;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    appVer,
                    style: appFont(context,
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                  Text(
                    'eSchool $eschoolVer',
                    style: appFont(context,
                      fontSize: 11,
                      color: colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              );
            },
          ),
          colorScheme: colorScheme,
        ),
        if (UpdateService.isSupported && !_api.isDemo) ...[
          _SettingsDivider(colorScheme: colorScheme),
          _SettingsRow(
            icon: Icons.system_update_rounded,
            title: l10n.checkForUpdates,
            trailing: Icon(
              Icons.arrow_forward_ios_rounded,
              size: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            onTap: () => _checkForUpdates(colorScheme, l10n),
            colorScheme: colorScheme,
          ),
        ],
      ],
    );
  }

  Future<void> _checkForUpdates(
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) async {
    HapticFeedback.lightImpact();

    // показываем лоадер
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => Center(
        child: Material(
          color: Colors.transparent,
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  l10n.checkingForUpdates,
                  style: appFont(context, fontSize: 14, color: colorScheme.onSurface),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    final update = await UpdateService.checkForUpdates(force: true);

    if (!mounted) return;
    Navigator.pop(context);

    if (update == null) {
      _showSnackBar(l10n.noUpdatesAvailable);
      return;
    }

    _showUpdateDialog(update, colorScheme, l10n);
  }

  Future<void> _showUpdateDialog(
    UpdateInfo update,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) async {
    // если сборка на модерации в ios, диалог другой
    if (update.isIOS && update.isTestFlightPending) {
      await showDialog(
        context: context,
        builder: (context) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.hourglass_top_rounded,
                  color: Colors.orange,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  l10n.updateAvailable,
                  style: appFont(context, fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
          content: Text(
            l10n.updatePendingReview(update.version),
            style: appFont(context,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
              height: 1.5,
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text('OK', style: appFont(context, fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      );
      return;
    }

    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                Icons.system_update_rounded,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                l10n.updateAvailable,
                style: appFont(context, fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              update.isIOS
                  ? l10n.updateAvailableTestFlight(update.version)
                  : l10n.updateAvailableMessage(update.version),
              style: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.5,
              ),
            ),
            if (update.releaseNotes != null &&
                update.releaseNotes!.isNotEmpty) ...[
              const SizedBox(height: 16),
              Text(
                l10n.whatsNew,
                style: appFont(context, fontWeight: FontWeight.w600, fontSize: 13),
              ),
              const SizedBox(height: 8),
              Container(
                constraints: const BoxConstraints(maxHeight: 150),
                child: SingleChildScrollView(
                  child: Text(
                    update.releaseNotes!,
                    style: appFont(context,
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                      height: 1.4,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, 'skip'),
            child: Text(
              l10n.skipUpdate,
              style: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, 'later'),
            child: Text(l10n.later, style: appFont(context)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, 'update'),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              update.isIOS ? l10n.openTestFlight : l10n.updateNow,
              style: appFont(context, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    if (result == 'skip') {
      await UpdateService.skipVersion(update.version);
    } else if (result == 'update') {
      if (update.isIOS) {
        // открываем ссылку на TestFlight
        final url = Uri.parse(update.downloadUrl);
        if (await canLaunchUrl(url)) {
          await launchUrl(url, mode: LaunchMode.externalApplication);
        }
      } else {
        await _downloadUpdate(update, colorScheme, l10n);
      }
    }
  }

  Future<void> _downloadUpdate(
    UpdateInfo update,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) async {
    final streamController = StreamController<int>.broadcast();

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          l10n.downloadingUpdate,
          style: appFont(context, fontWeight: FontWeight.w600),
        ),
        content: StreamBuilder<int>(
          stream: streamController.stream,
          initialData: 0,
          builder: (context, snapshot) {
            final percent = snapshot.data ?? 0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const CircularProgressIndicator(),
                const SizedBox(height: 16),
                Text(
                  '$percent%',
                  style: appFont(context,
                    fontSize: 24,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );

    try {
      await UpdateService.downloadAndInstall(update, (p) {
        streamController.add((p * 100).toInt());
      });
    } catch (e) {
      if (mounted) {
        Navigator.pop(context);
        _showSnackBar('${l10n.updateError}: $e');
      }
    } finally {
      await streamController.close();
    }
  }

  Widget _buildDeveloperCard(
    SettingsProvider settingsProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        _SettingsSwitch(
          icon: Icons.developer_mode_rounded,
          title: l10n.developerMode,
          subtitle: l10n.developerTools,
          value: settingsProvider.developerMode,
          onChanged: (v) => settingsProvider.setDeveloperMode(v),
          colorScheme: colorScheme,
        ),
      ],
    );
  }

  Widget _buildWebProxySection(
    SettingsProvider settings,
    ColorScheme colorScheme,
  ) {
    final serverController = TextEditingController(
      text: settings.webProxyServerUrl ?? '',
    );
    final tokenController = TextEditingController(text: settings.webProxyToken);

    return _SettingsCard(
      colorScheme: colorScheme,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Настройки прокси-сервера для веб-версии. Все запросы к eSchool идут через него.',
                style: appFont(context,
                  fontSize: 13,
                  color: colorScheme.onSurface.withValues(alpha: 0.55),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: serverController,
                style: appFont(context, fontSize: 14, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Адрес или код подключения',
                  helperText: 'Код выдаёт администратор сервера',
                  labelStyle: appFont(context,
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  hintText: 'https://ваш-сервер.ru',
                  hintStyle: appFont(context,
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: tokenController,
                readOnly: true,
                style: appFont(context, fontSize: 13, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  labelText: 'Токен',
                  labelStyle: appFont(context,
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  hintText: 'Введите API_TOKEN сервера',
                  hintStyle: appFont(context,
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colorScheme.primary,
                      width: 2,
                    ),
                  ),
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      Icons.copy_rounded,
                      size: 18,
                      color: colorScheme.primary,
                    ),
                    onPressed: () => Clipboard.setData(
                      ClipboardData(text: tokenController.text),
                    ),
                    tooltip: 'Скопировать токен',
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () async {
                        try {
                          serverController.text = await saveBrowserServerCode(
                            serverController.text,
                          );
                        } on FormatException catch (error) {
                          if (!mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text(error.message, style: appFont(context))),
                          );
                          return;
                        }
                        if (!mounted) return;
                        await settings.setWebProxyServerUrl(
                          serverController.text,
                        );
                        await settings.setWebProxyToken(tokenController.text);
                        ApiService().setWebProxy(
                          serverController.text,
                          tokenController.text,
                        );
                        _showSnackBar('Настройки прокси сохранены');
                      },
                      icon: const Icon(Icons.check_rounded, size: 16),
                      label: Text(
                        'Сохранить',
                        style: appFont(context,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: FilledButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title.toUpperCase(),
        style: appFont(context,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildThemeSelector(
    ThemeProvider themeProvider,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return _SettingsCard(
      colorScheme: colorScheme,
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            _ThemeOption(
              icon: Icons.light_mode_rounded,
              label: l10n.light,
              isSelected: themeProvider.themeMode == ThemeMode.light,
              onTap: () => themeProvider.setTheme(ThemeMode.light),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 12),
            _ThemeOption(
              icon: Icons.dark_mode_rounded,
              label: l10n.dark,
              isSelected: themeProvider.themeMode == ThemeMode.dark,
              onTap: () => themeProvider.setTheme(ThemeMode.dark),
              colorScheme: colorScheme,
            ),
            const SizedBox(width: 12),
            _ThemeOption(
              icon: Icons.contrast_rounded,
              label: l10n.auto,
              isSelected: themeProvider.themeMode == ThemeMode.system,
              onTap: () => themeProvider.setTheme(ThemeMode.system),
              colorScheme: colorScheme,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildWidgetSettingsSection(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    final widgetConfig = Provider.of<WidgetConfigProvider>(context);

    return Column(
      children: [
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _WidgetSettingsTile(
              icon: Icons.calendar_today_rounded,
              title: l10n.schedule,
              subtitle: l10n.lessonsForToday,
              value: widgetConfig.scheduleEnabled,
              onChanged: (v) => widgetConfig.setScheduleEnabled(v),
              colorScheme: colorScheme,
              expandedContent: widgetConfig.scheduleEnabled
                  ? _SettingsSwitch(
                      icon: Icons.person_outline_rounded,
                      title: l10n.showTeacher,
                      value: widgetConfig.showTeacherInSchedule,
                      onChanged: (v) =>
                          widgetConfig.setShowTeacherInSchedule(v),
                      colorScheme: colorScheme,
                      compact: true,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _WidgetSettingsTile(
              icon: Icons.assignment_rounded,
              title: l10n.homework,
              subtitle: l10n.upcomingAssignments,
              value: widgetConfig.homeworkEnabled,
              onChanged: (v) => widgetConfig.setHomeworkEnabled(v),
              colorScheme: colorScheme,
              expandedContent: widgetConfig.homeworkEnabled
                  ? Column(
                      children: [
                        _SettingsDropdown(
                          title: l10n.count,
                          value: widgetConfig.homeworkItemsCount,
                          items: const [3, 5, 7, 10],
                          onChanged: (v) =>
                              widgetConfig.setHomeworkItemsCount(v),
                          colorScheme: colorScheme,
                        ),
                        const SizedBox(height: 8),
                        _SettingsSwitch(
                          icon: Icons.schedule_rounded,
                          title: l10n.showDeadline,
                          value: widgetConfig.showDeadlineInHomework,
                          onChanged: (v) =>
                              widgetConfig.setShowDeadlineInHomework(v),
                          colorScheme: colorScheme,
                          compact: true,
                        ),
                      ],
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _WidgetSettingsTile(
              icon: Icons.grade_rounded,
              title: l10n.grades,
              subtitle: l10n.averageScores,
              value: widgetConfig.gradesEnabled,
              onChanged: (v) => widgetConfig.setGradesEnabled(v),
              colorScheme: colorScheme,
              expandedContent: widgetConfig.gradesEnabled
                  ? _SettingsDropdown(
                      title: l10n.subjects,
                      value: widgetConfig.gradesSubjectsCount,
                      items: const [4, 6, 8, 10],
                      onChanged: (v) => widgetConfig.setGradesSubjectsCount(v),
                      colorScheme: colorScheme,
                    )
                  : null,
            ),
          ],
        ),
        const SizedBox(height: 8),
        _SettingsCard(
          colorScheme: colorScheme,
          children: [
            _SettingsRow(
              icon: Icons.refresh_rounded,
              title: l10n.updateWidgets,
              subtitle: l10n.syncNow,
              onTap: () async {
                HapticFeedback.lightImpact();
                try {
                  await WidgetSyncService.instance.refresh(
                    bells: context.read<BellScheduleProvider>(),
                    settings: context.read<SettingsProvider>(),
                    config: widgetConfig.config,
                    force: true,
                  );
                  if (mounted) _showSnackBar(l10n.widgetsUpdated);
                } catch (_) {
                  if (mounted) _showSnackBar('Не удалось обновить виджеты. Попробуйте ещё раз.');
                }
              },
              colorScheme: colorScheme,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _buildWidgetHint(colorScheme),
      ],
    );
  }

  Widget _buildWidgetHint(ColorScheme colorScheme) {
    final hint = _getWidgetInstructions();
    if (hint.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.lightbulb_outline_rounded,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              hint,
              style: appFont(context,
                fontSize: 13,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _getWidgetInstructions() {
    if (kIsWeb) return "";
    if (Platform.isIOS) {
      return "Удерживайте главный экран, нажмите + и найдите reSchool";
    } else if (Platform.isAndroid) {
      return "Удерживайте главный экран, выберите «Виджеты» и найдите reSchool";
    } else if (Platform.isMacOS) {
      return "Нажмите на дату в строке меню и выберите «Редактировать виджеты»";
    }
    return "";
  }
}

// компоненты настроек

class _SettingsCard extends StatelessWidget {
  final List<Widget> children;
  final ColorScheme colorScheme;
  final EdgeInsets padding;

  const _SettingsCard({
    required this.children,
    required this.colorScheme,
    this.padding = const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: appCardDecoration(context),
      padding: padding,
      child: Column(children: children),
    );
  }
}

class _SettingsDivider extends StatelessWidget {
  final ColorScheme colorScheme;

  const _SettingsDivider({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: 1,
      thickness: 1,
      indent: 56,
      color: colorScheme.outline.withValues(alpha: 0.08),
    );
  }
}

class _SettingsRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final ColorScheme colorScheme;

  const _SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final iconColor = colorScheme.primary;
    final bgColor = colorScheme.primary.withValues(alpha: 0.1);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: bgColor,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: iconColor),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: appFont(context,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        style: appFont(context,
                          fontSize: 13,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _SettingsSwitch extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  final bool compact;

  const _SettingsSwitch({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: compact ? 8 : 10),
      child: Row(
        children: [
          Container(
            width: compact ? 32 : 36,
            height: compact ? 32 : 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(compact ? 8 : 10),
            ),
            child: Icon(
              icon,
              size: compact ? 16 : 18,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: appFont(context,
                    fontSize: compact ? 14 : 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (subtitle != null)
                  Text(
                    subtitle!,
                    style: appFont(context,
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
          Transform.scale(
            scale: compact ? 0.85 : 0.9,
            child: Switch.adaptive(
              value: value,
              onChanged: (v) {
                HapticFeedback.selectionClick();
                onChanged(v);
              },
              activeThumbColor: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeOption extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ThemeOption({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outline.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 22,
                color: isSelected
                    ? colorScheme.primary
                    : colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: appFont(context,
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WidgetSettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;
  final ColorScheme colorScheme;
  final Widget? expandedContent;

  const _WidgetSettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
    required this.colorScheme,
    this.expandedContent,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 18, color: colorScheme.primary),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: appFont(context,
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: appFont(context,
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Transform.scale(
                scale: 0.9,
                child: Switch.adaptive(
                  value: value,
                  onChanged: (v) {
                    HapticFeedback.selectionClick();
                    onChanged(v);
                  },
                  activeThumbColor: colorScheme.primary,
                ),
              ),
            ],
          ),
        ),
        if (expandedContent != null)
          Padding(
            padding: const EdgeInsets.only(left: 60, right: 12, bottom: 12),
            child: expandedContent!,
          ),
      ],
    );
  }
}

class _SettingsDropdown extends StatelessWidget {
  final String title;
  final int value;
  final List<int> items;
  final ValueChanged<int> onChanged;
  final ColorScheme colorScheme;

  const _SettingsDropdown({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          title,
          style: appFont(context,
            fontSize: 14,
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: DropdownButton<int>(
            value: value,
            underline: const SizedBox(),
            isDense: true,
            style: appFont(context,
              fontSize: 14,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
            dropdownColor: colorScheme.surface,
            items: items
                .map((n) => DropdownMenuItem(value: n, child: Text('$n', style: appFont(context))))
                .toList(),
            onChanged: (v) {
              if (v != null) {
                HapticFeedback.selectionClick();
                onChanged(v);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _ObsidianChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _ObsidianChip({
    required this.label,
    required this.icon,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: colorScheme.primary),
            const SizedBox(width: 5),
            Text(
              label,
              style: appFont(context,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ObsidianVaultDialog extends StatefulWidget {
  final SettingsProvider settingsProvider;
  final ColorScheme colorScheme;

  const _ObsidianVaultDialog({
    required this.settingsProvider,
    required this.colorScheme,
  });

  @override
  State<_ObsidianVaultDialog> createState() => _ObsidianVaultDialogState();
}

class _ObsidianVaultDialogState extends State<_ObsidianVaultDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settingsProvider.obsidianVault ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final settingsProvider = widget.settingsProvider;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Название хранилища Obsidian',
        style: appFont(context, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Точное название хранилища (vault) Obsidian. Нужно для корректного открытия на Mac и других платформах. Оставьте пустым для автовыбора.',
            style: appFont(context,
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: appFont(context, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Например: My Vault',
              hintStyle: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              prefixIcon: Icon(
                Icons.inventory_2_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: appFont(context, color: colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        if (settingsProvider.obsidianVault != null)
          TextButton(
            onPressed: () async {
              await settingsProvider.setObsidianVault(null);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('Сбросить', style: appFont(context, color: colorScheme.error)),
          ),
        FilledButton(
          onPressed: () async {
            await settingsProvider.setObsidianVault(_controller.text);
            if (context.mounted) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text('Сохранить', style: appFont(context, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

class _ObsidianPathDialog extends StatefulWidget {
  final SettingsProvider settingsProvider;
  final ColorScheme colorScheme;

  const _ObsidianPathDialog({
    required this.settingsProvider,
    required this.colorScheme,
  });

  @override
  State<_ObsidianPathDialog> createState() => _ObsidianPathDialogState();
}

class _ObsidianPathDialogState extends State<_ObsidianPathDialog> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.settingsProvider.obsidianPath ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;
    final settingsProvider = widget.settingsProvider;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(
        'Путь для экспорта в Obsidian',
        style: appFont(context, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Папка внутри хранилища Obsidian, куда будут сохраняться заметки дневника. Оставьте пустым для корня хранилища.',
            style: appFont(context,
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
              height: 1.4,
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            autofocus: true,
            style: appFont(context, fontSize: 15),
            decoration: InputDecoration(
              hintText: 'Например: Школа/Дневник',
              hintStyle: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.primary, width: 2),
              ),
              prefixIcon: Icon(
                Icons.folder_open_outlined,
                color: colorScheme.primary,
                size: 20,
              ),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Отмена',
            style: appFont(context, color: colorScheme.onSurface.withValues(alpha: 0.6)),
          ),
        ),
        if (settingsProvider.obsidianPath != null)
          TextButton(
            onPressed: () async {
              await settingsProvider.setObsidianPath(null);
              if (context.mounted) Navigator.pop(context);
            },
            child: Text('Сбросить', style: appFont(context, color: colorScheme.error)),
          ),
        FilledButton(
          onPressed: () async {
            await settingsProvider.setObsidianPath(_controller.text);
            if (context.mounted) Navigator.pop(context);
          },
          style: FilledButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          child: Text('Сохранить', style: appFont(context, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}
