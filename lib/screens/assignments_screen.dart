import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../viewmodels/assignments_viewmodel.dart';
import '../models/homework_models.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/assignments_sidebar.dart';
import 'homework_detail_screen.dart';

class AssignmentsScreen extends StatefulWidget {
  const AssignmentsScreen({super.key});

  @override
  State<AssignmentsScreen> createState() => _AssignmentsScreenState();
}

class _AssignmentsScreenState extends State<AssignmentsScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  DateTime? _selectedDate;
  String? _selectedSubject;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeOut,
    );
    _animationController.forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Provider.of<AssignmentsViewModel>(context, listen: false).loadAssignments();
    });
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  List<String> _getAvailableSubjects(List<HomeworkItem> items) {
    final subjects = items.map((item) => item.subject).toSet().toList();
    subjects.sort();
    return subjects;
  }

  Map<DateTime, List<HomeworkItem>> _groupByDate(List<HomeworkItem> items) {
    final Map<DateTime, List<HomeworkItem>> grouped = {};
    for (var item in items) {
      final dateKey = DateTime(item.date.year, item.date.month, item.date.day);
      if (!grouped.containsKey(dateKey)) {
        grouped[dateKey] = [];
      }
      grouped[dateKey]!.add(item);
    }
    return grouped;
  }

  String _formatDateHeader(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) {
      return l10n.today;
    } else if (dateOnly == yesterday) {
      return l10n.yesterday;
    } else if (dateOnly == tomorrow) {
      return l10n.tomorrow;
    } else {
      return DateFormat('d MMMM', l10n.locale.languageCode).format(date);
    }
  }

  String _getWeekday(DateTime date, AppLocalizations l10n) {
    return DateFormat('EEEE', l10n.locale.languageCode).format(date);
  }

  void _showPeriodSheet(BuildContext context, AssignmentsViewModel vm, AppLocalizations l10n) {
    HapticFeedback.selectionClick();
    DateTime tempStart = vm.startDate;
    DateTime tempEnd = vm.endDate;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setModalState) {
          final colorScheme = Theme.of(ctx).colorScheme;

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
            child: Container(
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [

                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 24),

                  Text(
                    l10n.period,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        _DatePickerTile(
                          label: l10n.start,
                          date: tempStart,
                          locale: l10n.locale,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: tempStart,
                              firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              locale: l10n.locale,
                            );
                            if (picked != null) {
                              setModalState(() => tempStart = picked);
                            }
                          },
                        ),
                        const SizedBox(height: 12),
                        _DatePickerTile(
                          label: l10n.end,
                          date: tempEnd,
                          locale: l10n.locale,
                          onTap: () async {
                            HapticFeedback.selectionClick();
                            final picked = await showDatePicker(
                              context: ctx,
                              initialDate: tempEnd,
                              firstDate: DateTime.now().subtract(const Duration(days: 365 * 3)),
                              lastDate: DateTime.now().add(const Duration(days: 365)),
                              locale: l10n.locale,
                            );
                            if (picked != null) {
                              setModalState(() => tempEnd = picked);
                            }
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: _QuickPeriodChip(
                            label: l10n.week,
                            isSelected: false,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final now = DateTime.now();
                              setModalState(() {
                                tempStart = now.subtract(const Duration(days: 7));
                                tempEnd = now;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickPeriodChip(
                            label: l10n.month,
                            isSelected: false,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final now = DateTime.now();
                              setModalState(() {
                                tempStart = now.subtract(const Duration(days: 30));
                                tempEnd = now;
                              });
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: _QuickPeriodChip(
                            label: l10n.threeMonths,
                            isSelected: false,
                            onTap: () {
                              HapticFeedback.selectionClick();
                              final now = DateTime.now();
                              setModalState(() {
                                tempStart = now.subtract(const Duration(days: 90));
                                tempEnd = now;
                              });
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),

                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: SizedBox(
                      width: double.infinity,
                      child: Material(
                        color: colorScheme.primary,
                        borderRadius: BorderRadius.circular(14),
                        child: InkWell(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            vm.updateDateRange(tempStart, tempEnd);
                            Navigator.pop(ctx);
                          },
                          borderRadius: BorderRadius.circular(14),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 16),
                            child: Center(
                              child: Text(
                                l10n.apply,
                                style: GoogleFonts.inter(
                                  fontSize: 16,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onPrimary,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Consumer<AssignmentsViewModel>(
      builder: (context, vm, child) {
        final groupedItems = _groupByDate(vm.items);
        final sortedDates = groupedItems.keys.toList()..sort((a, b) => b.compareTo(a));

        return Scaffold(
          backgroundColor: colorScheme.surface,
          body: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ResponsiveLayout(
                mobile: _buildMobileLayout(vm, groupedItems, sortedDates, colorScheme, l10n),
                desktop: _buildDesktopLayout(vm, groupedItems, sortedDates, colorScheme, l10n),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildMobileLayout(
    AssignmentsViewModel vm,
    Map<DateTime, List<HomeworkItem>> groupedItems,
    List<DateTime> sortedDates,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    const padding = 24.0;

    return RefreshIndicator(
      onRefresh: vm.loadAssignments,
      color: colorScheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.assignments,
                    style: GoogleFonts.outfit(
                      fontSize: 34,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.homeworkTitle,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ),

          SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.fromLTRB(padding, 16, padding, 8),
              child: _PeriodCard(
                startDate: vm.startDate,
                endDate: vm.endDate,
                onTap: () => _showPeriodSheet(context, vm, l10n),
              ),
            ),
          ),

          if (vm.isLoading)
            SliverFillRemaining(child: _LoadingState(l10n: l10n))
          else if (vm.error != null)
            SliverFillRemaining(
              child: _ErrorState(
                error: vm.error!,
                onRetry: vm.loadAssignments,
                l10n: l10n,
              ),
            )
          else if (vm.items.isEmpty)
            SliverFillRemaining(child: _EmptyState(l10n: l10n))
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  int currentIndex = 0;
                  for (var date in sortedDates) {
                    final items = groupedItems[date]!;

                    if (currentIndex == index) {
                      return _DateHeader(
                        title: _formatDateHeader(date, l10n),
                        weekday: _getWeekday(date, l10n),
                        date: date,
                      );
                    }
                    currentIndex++;

                    for (int i = 0; i < items.length; i++) {
                      if (currentIndex == index) {
                        return Padding(
                          padding: EdgeInsets.fromLTRB(padding, 0, padding, 12),
                          child: _HomeworkCard(item: items[i], l10n: l10n),
                        );
                      }
                      currentIndex++;
                    }
                  }
                  return null;
                },
                childCount: sortedDates.fold<int>(
                  0,
                  (sum, date) => sum + 1 + groupedItems[date]!.length,
                ),
              ),
            ),

          const SliverToBoxAdapter(child: SizedBox(height: 100)),
        ],
      ),
    );
  }

  Widget _buildDesktopLayout(
    AssignmentsViewModel vm,
    Map<DateTime, List<HomeworkItem>> groupedItems,
    List<DateTime> sortedDates,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    if (vm.isLoading && vm.items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loadingAssignments,
              style: GoogleFonts.inter(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (vm.error != null && vm.items.isEmpty) {
      return _ErrorState(error: vm.error!, onRetry: vm.loadAssignments, l10n: l10n);
    }

    final filteredItems = _selectedSubject != null
        ? vm.items.where((item) => item.subject == _selectedSubject).toList()
        : vm.items;
    final filteredGroupedItems = _groupByDate(filteredItems);
    final filteredSortedDates = filteredGroupedItems.keys.toList()..sort((a, b) => b.compareTo(a));
    final availableSubjects = _getAvailableSubjects(vm.items);

    return Row(
      children: [

        AssignmentsSidebar(
          startDate: vm.startDate,
          endDate: vm.endDate,
          selectedDate: _selectedDate,
          groupedItems: filteredGroupedItems,
          sortedDates: filteredSortedDates,
          onSelectDate: (date) {
            setState(() {
              _selectedDate = date;
            });
          },
          onChangePeriod: () => _showPeriodSheet(context, vm, l10n),
          totalCount: filteredItems.length,
          selectedSubject: _selectedSubject,
          availableSubjects: availableSubjects,
          onSelectSubject: (subject) {
            setState(() {
              _selectedSubject = subject;
              _selectedDate = null;
            });
          },
        ),

        Expanded(
          child: _buildDesktopContent(
            vm,
            filteredGroupedItems,
            filteredSortedDates,
            colorScheme,
            l10n,
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopContent(
    AssignmentsViewModel vm,
    Map<DateTime, List<HomeworkItem>> groupedItems,
    List<DateTime> sortedDates,
    ColorScheme colorScheme,
    AppLocalizations l10n,
  ) {
    List<DateTime> displayDates;
    if (_selectedDate != null) {
      displayDates = sortedDates.where((d) =>
        d.year == _selectedDate!.year &&
        d.month == _selectedDate!.month &&
        d.day == _selectedDate!.day
      ).toList();
    } else {
      displayDates = sortedDates;
    }

    if (vm.items.isEmpty) {
      return _EmptyState(l10n: l10n);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        _buildDesktopHeader(colorScheme, l10n, displayDates, groupedItems),

        Expanded(
          child: RefreshIndicator(
            onRefresh: vm.loadAssignments,
            color: colorScheme.primary,
            child: displayDates.isEmpty
                ? Center(
                    child: Text(
                      l10n.noAssignments,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(32, 0, 32, 32),
                    itemCount: displayDates.fold<int>(
                      0,
                      (sum, date) => sum + 1 + (groupedItems[date]?.length ?? 0),
                    ),
                    itemBuilder: (context, index) {
                      int currentIndex = 0;
                      for (var date in displayDates) {
                        final items = groupedItems[date] ?? [];

                        if (currentIndex == index) {
                          return _DesktopDateHeader(
                            title: _formatDateHeader(date, l10n),
                            weekday: _getWeekday(date, l10n),
                            date: date,
                            itemCount: items.length,
                          );
                        }
                        currentIndex++;

                        for (int i = 0; i < items.length; i++) {
                          if (currentIndex == index) {
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 12),
                              child: _DesktopHomeworkCard(
                                item: items[i],
                                l10n: l10n,
                              ),
                            );
                          }
                          currentIndex++;
                        }
                      }
                      return null;
                    },
                  ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopHeader(
    ColorScheme colorScheme,
    AppLocalizations l10n,
    List<DateTime> displayDates,
    Map<DateTime, List<HomeworkItem>> groupedItems,
  ) {
    final itemCount = displayDates.fold<int>(
      0,
      (sum, date) => sum + (groupedItems[date]?.length ?? 0),
    );

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
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _selectedDate != null
                    ? _formatDateHeader(_selectedDate!, l10n)
                    : l10n.allAssignments,
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _selectedDate != null
                    ? _getWeekday(_selectedDate!, l10n)
                    : '${itemCount} ${_getTasksWord(itemCount, l10n)}',
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const Spacer(),
          if (_selectedDate != null)
            GestureDetector(
              onTap: () {
                HapticFeedback.selectionClick();
                setState(() {
                  _selectedDate = null;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.clear_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.showAll,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
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

  String _getTasksWord(int count, AppLocalizations l10n) {
    final isRu = l10n.locale.languageCode == 'ru';
    if (!isRu) return count == 1 ? 'task' : 'tasks';

    final mod10 = count % 10;
    final mod100 = count % 100;

    if (mod10 == 1 && mod100 != 11) return 'задание';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'задания';
    }
    return 'заданий';
  }
}

class _PeriodCard extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final VoidCallback onTap;

  const _PeriodCard({
    required this.startDate,
    required this.endDate,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: isDark
                  ? [
                      colorScheme.primary.withValues(alpha: 0.15),
                      colorScheme.primary.withValues(alpha: 0.05),
                    ]
                  : [
                      colorScheme.primary.withValues(alpha: 0.12),
                      colorScheme.primary.withValues(alpha: 0.04),
                    ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.date_range_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Период',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${DateFormat('d MMM', 'ru').format(startDate)} — ${DateFormat('d MMM yyyy', 'ru').format(endDate)}',
                      style: GoogleFonts.inter(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DatePickerTile extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;
  final Locale locale;

  const _DatePickerTile({
    required this.label,
    required this.date,
    required this.onTap,
    required this.locale,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.05)
          : colorScheme.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.calendar_today_rounded,
                  color: colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      DateFormat('d MMMM yyyy', locale.languageCode).format(date),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.edit_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                size: 18,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickPeriodChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _QuickPeriodChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isSelected
          ? colorScheme.primary
          : isDark
              ? colorScheme.onSurface.withValues(alpha: 0.05)
              : colorScheme.onSurface.withValues(alpha: 0.03),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.inter(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: isSelected
                    ? colorScheme.onPrimary
                    : colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final String title;
  final String weekday;
  final DateTime date;

  const _DateHeader({
    required this.title,
    required this.weekday,
    required this.date,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final isToday = dateOnly == today;
    final padding = isDesktop(context) ? 32.0 : 24.0;

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 24, padding, 12),
      child: Row(
        children: [
          if (isToday)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                'Сегодня',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onPrimary,
                ),
              ),
            )
          else
            Text(
              title,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          const SizedBox(width: 10),
          if (!isToday)
            Text(
              weekday,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Container(
              height: 1,
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
        ],
      ),
    );
  }
}

class _HomeworkCard extends StatelessWidget {
  final HomeworkItem item;
  final AppLocalizations l10n;

  const _HomeworkCard({required this.item, required this.l10n});

  Color _getSubjectColor(String subject, ColorScheme colorScheme) {
    final hash = subject.hashCode;
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF06B6D4),
      const Color(0xFF3B82F6),
      const Color(0xFFEF4444),
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subjectColor = _getSubjectColor(item.subject, colorScheme);

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.03)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => HomeworkDetailScreen(
                subject: item.subject,
                text: item.text,
                deadline: item.deadline,
                files: item.files,
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [

              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [

                    Container(
                      width: 4,
                      height: 44,
                      decoration: BoxDecoration(
                        color: subjectColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.subject,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                    ),
                  ],
                ),
              ),

              if (item.text.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                  child: Text(
                    item.text,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      height: 1.5,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),

              if (item.files.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colorScheme.onSurface.withValues(alpha: 0.03),
                    borderRadius: const BorderRadius.vertical(
                      bottom: Radius.circular(16),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(
                          Icons.attach_file_rounded,
                          size: 14,
                          color: colorScheme.primary,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        _getFilesText(item.files.length, l10n),
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _getFilesText(int count, AppLocalizations l10n) {
    if (count == 1) return '1 ${l10n.attachment1}';
    if (count >= 2 && count <= 4) return '$count ${l10n.attachment24}';
    return '$count ${l10n.attachment5}';
  }
}

class _LoadingState extends StatelessWidget {
  final AppLocalizations l10n;
  const _LoadingState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 48,
            height: 48,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: colorScheme.primary,
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.loadingAssignments,
            style: GoogleFonts.inter(
              fontSize: 15,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error;
  final VoidCallback onRetry;
  final AppLocalizations l10n;

  const _ErrorState({required this.error, required this.onRetry, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.error_outline_rounded,
                size: 36,
                color: colorScheme.error,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.loadingError,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 24),
            Material(
              color: colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
              child: InkWell(
                onTap: () {
                  HapticFeedback.lightImpact();
                  onRetry();
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 18,
                        color: colorScheme.onPrimary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        l10n.retry,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final AppLocalizations l10n;
  const _EmptyState({required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.assignment_outlined,
                size: 40,
                color: colorScheme.primary.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              l10n.noAssignments,
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noAssignmentsInPeriod,
              textAlign: TextAlign.center,
              style: GoogleFonts.inter(
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopDateHeader extends StatelessWidget {
  final String title;
  final String weekday;
  final DateTime date;
  final int itemCount;

  const _DesktopDateHeader({
    required this.title,
    required this.weekday,
    required this.date,
    required this.itemCount,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final isToday = dateOnly == today;

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 24, 0, 16),
      child: Row(
        children: [

          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: isToday
                  ? colorScheme.primary
                  : colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  date.day.toString(),
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: isToday ? colorScheme.onPrimary : colorScheme.primary,
                    height: 1,
                  ),
                ),
                Text(
                  DateFormat.E('ru').format(date).toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isToday
                        ? colorScheme.onPrimary.withValues(alpha: 0.8)
                        : colorScheme.primary.withValues(alpha: 0.8),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                '$weekday • $itemCount ${itemCount == 1 ? 'задание' : 'заданий'}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
          const Spacer(),
          Container(
            height: 1,
            width: 100,
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
        ],
      ),
    );
  }
}

class _DesktopHomeworkCard extends StatelessWidget {
  final HomeworkItem item;
  final AppLocalizations l10n;

  const _DesktopHomeworkCard({required this.item, required this.l10n});

  Color _getSubjectColor(String subject) {
    final hash = subject.hashCode;
    final colors = [
      const Color(0xFF6366F1),
      const Color(0xFF8B5CF6),
      const Color(0xFFEC4899),
      const Color(0xFFF59E0B),
      const Color(0xFF10B981),
      const Color(0xFF06B6D4),
      const Color(0xFF3B82F6),
      const Color(0xFFEF4444),
    ];
    return colors[hash.abs() % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subjectColor = _getSubjectColor(item.subject);

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.03)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(18),
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();

          showDialog(
            context: context,
            builder: (context) => Dialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(24),
              ),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600, maxHeight: 700),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(24),
                  child: HomeworkDetailScreen(
                    subject: item.subject,
                    text: item.text,
                    deadline: item.deadline,
                    files: item.files,
                    isDialog: true,
                  ),
                ),
              ),
            ),
          );
        },
        borderRadius: BorderRadius.circular(18),
        child: IntrinsicHeight(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: colorScheme.outline.withValues(alpha: 0.08),
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(17),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [

                  Container(
                    width: 8,
                    color: subjectColor,
                  ),

                Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [

                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.subject,
                                  style: GoogleFonts.inter(
                                    fontSize: 17,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          if (item.files.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: colorScheme.primary.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.attach_file_rounded,
                                    size: 16,
                                    color: colorScheme.primary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    item.files.length.toString(),
                                    style: GoogleFonts.inter(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),

                      if (item.text.isNotEmpty) ...[
                        const SizedBox(height: 14),
                        Text(
                          item.text,
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            height: 1.6,
                            color: colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
              ),

                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Icon(
                      Icons.arrow_forward_rounded,
                      color: colorScheme.onSurface.withValues(alpha: 0.3),
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}