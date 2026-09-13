import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../l10n/app_localizations.dart';
import '../viewmodels/diary_viewmodel.dart';
import '../providers/bell_schedule_provider.dart';
import '../providers/custom_homework_provider.dart';
import '../providers/settings_provider.dart';
import '../widgets/week_strip.dart';
import '../widgets/lesson_card.dart';
import '../widgets/break_card.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/diary_sidebar.dart';
import '../utils/time_utils.dart';
import '../models/lesson_view_model.dart';
import '../services/diary_navigation_service.dart';
import '../services/obsidian_export_service.dart';
import '../utils/app_font.dart';

class DiaryScreen extends StatelessWidget {
  const DiaryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<SettingsProvider>(context, listen: false);
    final now = DateTime.now();
    final initialDate = settings.diaryInitialDay == 'tomorrow'
        ? now.add(const Duration(days: 1))
        : now;
    return ChangeNotifierProvider(
      create: (_) => DiaryViewModel(
        Provider.of<BellScheduleProvider>(context, listen: false),
        initialDate: initialDate,
      ),
      child: const DiaryView(),
    );
  }
}

class DiaryView extends StatefulWidget {
  const DiaryView({super.key});

  @override
  State<DiaryView> createState() => _DiaryViewState();
}

class _DiaryViewState extends State<DiaryView>
    with SingleTickerProviderStateMixin {
  late PageController _pageController;
  final DateTime _anchorDate = DateTime(2020, 1, 1);
  bool _isProgrammaticPageChange = false;
  Timer? _timer;
  DateTime? _lastLoadedWeekStart;
  String? _lastCloudConnection;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  int _getDateIndex(DateTime date) {
    final startOfDate = DateTime(date.year, date.month, date.day);
    final startOfAnchor = DateTime(
      _anchorDate.year,
      _anchorDate.month,
      _anchorDate.day,
    );
    return startOfDate.difference(startOfAnchor).inDays;
  }

  DateTime _getDateFromIndex(int index) {
    return _anchorDate.add(Duration(days: index));
  }

  void _loadCustomHomeworkForWeek(DateTime date) {
    final settings = context.read<SettingsProvider>();
    if (!settings.cloudHomeworkEnabled) return;
    final connection = '${settings.cloudServerUrl}:${settings.cloudApiToken}';
    if (_lastCloudConnection != connection) {
      _lastLoadedWeekStart = null;
      _lastCloudConnection = connection;
    }

    final weekStart = date.subtract(Duration(days: date.weekday - 1));

    // ту же неделю второй раз не грузим
    if (_lastLoadedWeekStart != null &&
        _lastLoadedWeekStart!.year == weekStart.year &&
        _lastLoadedWeekStart!.month == weekStart.month &&
        _lastLoadedWeekStart!.day == weekStart.day) {
      return;
    }

    _lastLoadedWeekStart = weekStart;
    // сюда заходят прямо из build, а провайдер дёргает notifyListeners
    // ещё до первого await, так что ждём конца кадра
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<CustomHomeworkProvider>().loadHomeworkForWeek(weekStart);
    });
  }

  @override
  void initState() {
    super.initState();
    _pageController = PageController();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();

    _timer = Timer.periodic(const Duration(seconds: 30), (timer) {
      if (mounted) setState(() {});
    });

    // своё домашнее задание на стартовую неделю
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final vm = context.read<DiaryViewModel>();
        _loadCustomHomeworkForWeek(vm.selectedDate);
        // если нас просили куда то перейти, например тапом по уведомлению
        _handlePendingNavigation();
      }
    });

    DiaryNavigationService.instance.pending.addListener(
      _handlePendingNavigation,
    );
  }

  void _handlePendingNavigation() {
    final req = DiaryNavigationService.instance.consume();
    if (req == null || !mounted) return;

    final vm = context.read<DiaryViewModel>();

    if (req.date != null) {
      final target = req.date!;
      _isProgrammaticPageChange = true;
      vm.selectDate(target);
      final index = _getDateIndex(target);
      if (_pageController.hasClients) {
        _pageController.animateToPage(
          index,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeInOut,
        );
      }
      Future.delayed(const Duration(milliseconds: 50), () {
        _isProgrammaticPageChange = false;
      });
    }

    if (req.subject != null) {
      final subject = req.subject!;
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted) return;
        final lessons = vm.getLessonsForDate(vm.selectedDate);
        final matches = lessons
            .where(
              (l) => l.subject.toLowerCase().contains(subject.toLowerCase()),
            )
            .toList();
        if (matches.isEmpty) return;
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => LessonDetailSheet(
            lesson: matches.first,
            lessonDate: vm.selectedDate,
          ),
        );
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final vm = context.read<DiaryViewModel>();
    final initialIndex = _getDateIndex(vm.selectedDate);
    if (_pageController.hasClients) {
      if ((_pageController.page?.round() ?? 0) != initialIndex &&
          !_isProgrammaticPageChange) {
        _pageController.jumpToPage(initialIndex);
      }
    } else {
      _pageController = PageController(initialPage: initialIndex);
    }
  }

  @override
  void dispose() {
    DiaryNavigationService.instance.pending.removeListener(
      _handlePendingNavigation,
    );
    _pageController.dispose();
    _animationController.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _exportToObsidian(DiaryViewModel vm) async {
    final lessons = vm.getLessonsForDate(vm.selectedDate);
    if (lessons.isEmpty) return;

    final colorScheme = Theme.of(context).colorScheme;

    // показываем снекбар с прогрессом
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.onInverseSurface,
              ),
            ),
            const SizedBox(width: 12),
             Text('Экспорт в Obsidian…', style: appFont(context)),
          ],
        ),
        duration: const Duration(seconds: 30),
        behavior: SnackBarBehavior.floating,
      ),
    );

    try {
      final settings = context.read<SettingsProvider>();
      final outputDir = settings.obsidianOutputDir;
      final showMarks = settings.obsidianShowMarks;

      if (outputDir != null && outputDir.isNotEmpty) {
        // пишем файл напрямую, плагин тут не нужен
        await ObsidianExportService.exportDayToDir(
          date: vm.selectedDate,
          lessons: lessons,
          outputDir: outputDir,
          showMarks: showMarks,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Сохранено в $outputDir', style: appFont(context)),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        final obsidianPath = settings.obsidianPath;
        final obsidianVault = settings.obsidianVault;
        await ObsidianExportService.exportDayToObsidian(
          date: vm.selectedDate,
          lessons: lessons,
          obsidianPath: obsidianPath,
          obsidianVault: obsidianVault,
          showMarks: showMarks,
        );
        if (!mounted) return;
        ScaffoldMessenger.of(context).hideCurrentSnackBar();
        ScaffoldMessenger.of(context).showSnackBar(
           SnackBar(
            content: Text('Открыто в Obsidian', style: appFont(context)),
            duration: Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Ошибка: $e', style: appFont(context)),
          duration: const Duration(seconds: 4),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<DiaryViewModel>();
    final colorScheme = Theme.of(context).colorScheme;

    // неделя сменилась, перечитываем своё домашнее задание
    _loadCustomHomeworkForWeek(vm.selectedDate);

    final targetIndex = _getDateIndex(vm.selectedDate);
    if (_pageController.hasClients) {
      final currentIndex = _pageController.page?.round() ?? targetIndex;
      if (currentIndex != targetIndex && !_isProgrammaticPageChange) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _isProgrammaticPageChange = true;
          _pageController
              .animateToPage(
                targetIndex,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
              )
              .then((_) => _isProgrammaticPageChange = false);
        });
      }
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: SafeArea(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: ResponsiveLayout(
            mobile: _buildMobileLayout(vm, colorScheme),
            desktop: _buildDesktopLayout(vm, colorScheme),
          ),
        ),
      ),
    );
  }

  /// мобильная вёрстка, всё в одну колонку
  Widget _buildMobileLayout(DiaryViewModel vm, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      children: [
        // шапка
        _buildMobileHeader(vm, colorScheme, l10n),

        // полоса недели
        _buildWeekSection(vm, colorScheme, isDark),

        // уроки
        Expanded(child: _buildLessonsPageView(vm, colorScheme)),
      ],
    );
  }

  /// десктопная вёрстка: боковая панель и содержимое
  Widget _buildDesktopLayout(DiaryViewModel vm, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Row(
      children: [
        // слева календарь и дни недели
        DiarySidebar(
          selectedDate: vm.selectedDate,
          currentWeek: vm.currentWeek,
          onSelectDate: vm.selectDate,
          onPreviousWeek: () => vm.changeWeek(-1),
          onNextWeek: () => vm.changeWeek(1),
          getLessonsForDate: vm.getLessonsForDate,
        ),

        // справа содержимое
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // шапка выбранного дня
              _buildDesktopHeader(vm, colorScheme, isDark, l10n),

              // список уроков
              Expanded(child: _buildDesktopLessonsList(vm, colorScheme)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHeader(
    DiaryViewModel vm,
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final now = DateTime.now();
    final isToday = vm.isSameDay(vm.selectedDate, now);
    final isYesterday = vm.isSameDay(
      vm.selectedDate,
      now.subtract(const Duration(days: 1)),
    );
    final isTomorrow = vm.isSameDay(
      vm.selectedDate,
      now.add(const Duration(days: 1)),
    );

    String dayLabel;
    if (isToday) {
      dayLabel = l10n.today;
    } else if (isYesterday) {
      dayLabel = l10n.yesterday;
    } else if (isTomorrow) {
      dayLabel = l10n.tomorrow;
    } else {
      dayLabel = DateFormat('EEEE', 'ru').format(vm.selectedDate);
    }

    final lessons = vm.getLessonsForDate(vm.selectedDate);
    final realLessons = lessons.where((l) => !l.isPlaceholder).toList();

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 24, 32, 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // про дату
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  dayLabel.substring(0, 1).toUpperCase() +
                      dayLabel.substring(1),
                  style: appFont(context,
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  DateFormat('d MMMM yyyy', 'ru').format(vm.selectedDate),
                  style: appFont(context,
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          // статистика и кнопки
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                if (realLessons.isNotEmpty)
                  _buildStatChip(
                    icon: Icons.school_outlined,
                    label: l10n.lessonsCount(realLessons.length),
                    colorScheme: colorScheme,
                  ),
                if (realLessons.isNotEmpty &&
                    realLessons.first.startTime.isNotEmpty)
                  _buildStatChip(
                    icon: Icons.schedule_outlined,
                    label:
                        '${realLessons.first.startTime} - ${realLessons.last.endTime}',
                    colorScheme: colorScheme,
                  ),
                if (context.watch<SettingsProvider>().obsidianEnabled)
                  Tooltip(
                    message: 'Экспорт в Obsidian',
                    child: TextButton.icon(
                      onPressed: () => _exportToObsidian(vm),
                      icon: const Icon(Icons.file_open_outlined, size: 18),
                      label:  Text('Obsidian', style: appFont(context)),
                      style: TextButton.styleFrom(
                        foregroundColor: colorScheme.primary,
                        backgroundColor: colorScheme.primary.withValues(
                          alpha: 0.08,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatChip({
    required IconData icon,
    required String label,
    required ColorScheme colorScheme,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: colorScheme.primary),
          const SizedBox(width: 8),
          Text(
            label,
            style: appFont(context,
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: colorScheme.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDesktopLessonsList(DiaryViewModel vm, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;
    final lessons = vm.getLessonsForDate(vm.selectedDate);

    if (vm.isLoading && lessons.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loading,
              style: appFont(context,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (lessons.isEmpty) {
      if (vm.error != null) {
        return _buildErrorState(vm.error!, colorScheme, l10n);
      }
      return _buildEmptyState(colorScheme, l10n);
    }

    return _buildLessonListContent(
      context,
      lessons,
      vm.selectedDate,
      colorScheme,
      isDesktop: true,
    );
  }

  Widget _buildMobileHeader(
    DiaryViewModel vm,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: vm.selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context)
                          .copyWith(colorScheme: colorScheme),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  vm.selectDate(picked);
                }
              },
              child: Row(
                children: [
                  Text(
                    DateFormat('LLLL yyyy', 'ru').format(vm.selectedDate),
                    style: appFont(context,
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ],
              ),
            ),
          ),
          _buildIconButton(
            icon: Icons.today_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              vm.selectDate(DateTime.now());
            },
            colorScheme: colorScheme,
            tooltip: l10n.today,
          ),
          const SizedBox(width: 4),
          if (context.watch<SettingsProvider>().obsidianEnabled)
            _buildIconButton(
              icon: Icons.file_open_outlined,
              onTap: () {
                HapticFeedback.lightImpact();
                _exportToObsidian(vm);
              },
              colorScheme: colorScheme,
              tooltip: 'Экспорт в Obsidian',
            ),
        ],
      ),
    );
  }

  Widget _buildIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    String? tooltip,
  }) {
    return Tooltip(
      message: tooltip ?? '',
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 22, color: colorScheme.primary),
        ),
      ),
    );
  }

  Widget _buildWeekSection(
    DiaryViewModel vm,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _buildWeekNavButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: () => vm.changeWeek(-1),
                  colorScheme: colorScheme,
                ),
                Text(
                  "${DateFormat('d MMM', 'ru').format(vm.currentWeek.first)} - ${DateFormat('d MMM', 'ru').format(vm.currentWeek.last)}",
                  style: appFont(context,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                _buildWeekNavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: () => vm.changeWeek(1),
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),
          WeekStrip(
            week: vm.currentWeek,
            selectedDate: vm.selectedDate,
            onSelect: vm.selectDate,
          ),
        ],
      ),
    );
  }

  Widget _buildWeekNavButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 20, color: colorScheme.primary),
      ),
    );
  }

  Widget _buildEmptyState(ColorScheme colorScheme, AppLocalizations l10n) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.weekend_rounded,
              size: 40,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.noLessons,
            style: appFont(context,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.noLessonsScheduled,
            style: appFont(context,
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    String error,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: colorScheme.error.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: colorScheme.error,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.loadingError,
            style: appFont(context,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              error,
              style: appFont(context,
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonsPageView(DiaryViewModel vm, ColorScheme colorScheme) {
    final l10n = AppLocalizations.of(context)!;

    return PageView.builder(
      controller: _pageController,
      onPageChanged: (index) {
        if (!_isProgrammaticPageChange) {
          final newDate = _getDateFromIndex(index);
          if (!vm.isSameDay(newDate, vm.selectedDate)) {
            vm.selectDate(newDate);
          }
        }
      },
      itemBuilder: (context, index) {
        final date = _getDateFromIndex(index);
        final lessons = vm.getLessonsForDate(date);

        if (vm.isLoading && lessons.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CircularProgressIndicator(color: colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  l10n.loading,
                  style: appFont(context,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          );
        }

        if (lessons.isEmpty) {
          if (vm.error != null) {
            return _buildErrorState(vm.error!, colorScheme, l10n);
          }
          return _buildEmptyState(colorScheme, l10n);
        }

        return _buildLessonListContent(context, lessons, date, colorScheme);
      },
    );
  }

  Widget _buildLessonListContent(
    BuildContext context,
    List<LessonViewModel> lessons,
    DateTime date,
    ColorScheme colorScheme, {
    bool isDesktop = false,
  }) {
    final now = context.watch<BellScheduleProvider>().now;
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    final customHomeworkProvider = context.watch<CustomHomeworkProvider>();

    final List<Widget> items = [];

    for (int i = 0; i < lessons.length; i++) {
      final lesson = lessons[i];
      bool isNow = false;

      if (isToday) {
        if (lesson.startTime.isNotEmpty && lesson.endTime.isNotEmpty) {
          isNow = TimeUtils.isTimeBetween(
            lesson.startTime,
            lesson.endTime,
            now,
          );
        }
      }

      // сколько добавленных домашних заданий у этого урока
      final customHomeworkCount = customHomeworkProvider
          .getHomeworkForSubjectAndDate(lesson.subject, date)
          .length;

      items.add(
        LessonCard(
          lesson: lesson,
          isNow: isNow,
          isDesktop: isDesktop,
          customHomeworkCount: customHomeworkCount,
          onTap: () {
            HapticFeedback.lightImpact();
            if (isDesktop) {
              // на десктопе вместо шторки показываем диалог
              showDialog(
                context: context,
                builder: (context) => Dialog(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 500),
                    child: LessonDetailSheet(lesson: lesson, lessonDate: date),
                  ),
                ),
              );
            } else {
              showModalBottomSheet(
                context: context,
                isScrollControlled: true,
                backgroundColor: Colors.transparent,
                builder: (context) =>
                    LessonDetailSheet(lesson: lesson, lessonDate: date),
              );
            }
          },
        ),
      );

      if (isToday && i < lessons.length - 1) {
        final nextLesson = lessons[i + 1];
        if (lesson.endTime.isNotEmpty && nextLesson.startTime.isNotEmpty) {
          final isBreakNow = TimeUtils.isTimeBetween(
            lesson.endTime,
            nextLesson.startTime,
            now,
          );

          if (isBreakNow) {
            final startMin = TimeUtils.toMinutes(lesson.endTime);
            final endMin = TimeUtils.toMinutes(nextLesson.startTime);
            final duration = endMin - startMin;

            items.add(
              BreakCard(
                start: lesson.endTime,
                end: nextLesson.startTime,
                duration: duration > 0 ? duration : 0,
              ),
            );
          }
        }
      }
    }

    return ListView(
      padding: EdgeInsets.only(
        top: isDesktop ? 24 : 16,
        bottom: 20,
        left: isDesktop ? 12 : 0,
        right: isDesktop ? 12 : 0,
      ),
      children: items,
    );
  }
}
