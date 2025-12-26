import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/homework_models.dart';

class AssignmentsSidebar extends StatelessWidget {
  final DateTime startDate;
  final DateTime endDate;
  final DateTime? selectedDate;
  final Map<DateTime, List<HomeworkItem>> groupedItems;
  final List<DateTime> sortedDates;
  final ValueChanged<DateTime?> onSelectDate;
  final VoidCallback onChangePeriod;
  final int totalCount;
  final String? selectedSubject;
  final List<String> availableSubjects;
  final ValueChanged<String?> onSelectSubject;

  const AssignmentsSidebar({
    super.key,
    required this.startDate,
    required this.endDate,
    required this.selectedDate,
    required this.groupedItems,
    required this.sortedDates,
    required this.onSelectDate,
    required this.onChangePeriod,
    required this.totalCount,
    required this.selectedSubject,
    required this.availableSubjects,
    required this.onSelectSubject,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: isDark ? colorScheme.surface : colorScheme.surfaceContainerLowest,
        border: Border(
          right: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          _buildHeader(context, colorScheme, l10n),

          _buildPeriodCard(context, colorScheme, isDark, l10n),

          _buildSubjectFilter(context, colorScheme, isDark, l10n),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 1,
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),

          const SizedBox(height: 12),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  l10n.byDates.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),

                GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelectDate(null);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: selectedDate == null
                          ? colorScheme.primary.withValues(alpha: 0.15)
                          : colorScheme.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      l10n.all,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: selectedDate == null
                            ? colorScheme.primary
                            : colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: sortedDates.isEmpty
                ? Center(
                    child: Text(
                      l10n.noAssignments,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: sortedDates.length,
                    itemBuilder: (context, index) {
                      final date = sortedDates[index];
                      final items = groupedItems[date] ?? [];
                      final isSelected = selectedDate != null &&
                          _isSameDay(date, selectedDate!);
                      return _DateListItem(
                        date: date,
                        items: items,
                        isSelected: isSelected,
                        onTap: () => onSelectDate(date),
                        l10n: l10n,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.assignments,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            l10n.homeworkTitle,
            style: GoogleFonts.inter(
              fontSize: 13,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPeriodCard(
      BuildContext context, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          onChangePeriod();
        },
        child: Container(
          padding: const EdgeInsets.all(14),
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
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.primary.withValues(alpha: 0.15),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.date_range_rounded,
                  color: colorScheme.primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.period,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    Text(
                      '${DateFormat('d MMM', 'ru').format(startDate)} — ${DateFormat('d MMM', 'ru').format(endDate)}',
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSubjectFilter(
      BuildContext context, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    if (availableSubjects.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.school_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                '$totalCount ${l10n.tasksLabel}',
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),

        SizedBox(
          height: 36,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: availableSubjects.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                final isSelected = selectedSubject == null;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelectSubject(null);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary
                            : isDark
                                ? colorScheme.onSurface.withValues(alpha: 0.05)
                                : colorScheme.onSurface.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.outline.withValues(alpha: 0.1),
                        ),
                      ),
                      child: Text(
                        l10n.all,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: isSelected
                              ? colorScheme.onPrimary
                              : colorScheme.onSurface.withValues(alpha: 0.7),
                        ),
                      ),
                    ),
                  ),
                );
              }

              final subject = availableSubjects[index - 1];
              final isSelected = selectedSubject == subject;
              final subjectColor = _getSubjectColor(subject);

              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: GestureDetector(
                  onTap: () {
                    HapticFeedback.selectionClick();
                    onSelectSubject(subject);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? subjectColor.withValues(alpha: 0.15)
                          : isDark
                              ? colorScheme.onSurface.withValues(alpha: 0.05)
                              : colorScheme.onSurface.withValues(alpha: 0.03),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected
                            ? subjectColor.withValues(alpha: 0.5)
                            : colorScheme.outline.withValues(alpha: 0.1),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: subjectColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _shortenSubject(subject),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                            color: isSelected
                                ? subjectColor
                                : colorScheme.onSurface.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }

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

  String _shortenSubject(String subject) {
    if (subject.length <= 12) return subject;
    return '${subject.substring(0, 10)}...';
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DateListItem extends StatelessWidget {
  final DateTime date;
  final List<HomeworkItem> items;
  final bool isSelected;
  final VoidCallback onTap;
  final AppLocalizations l10n;

  const _DateListItem({
    required this.date,
    required this.items,
    required this.isSelected,
    required this.onTap,
    required this.l10n,
  });

  String _formatDate(DateTime date, AppLocalizations l10n) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final tomorrow = today.add(const Duration(days: 1));
    final dateOnly = DateTime(date.year, date.month, date.day);

    if (dateOnly == today) return l10n.today;
    if (dateOnly == yesterday) return l10n.yesterday;
    if (dateOnly == tomorrow) return l10n.tomorrow;
    return DateFormat('d MMMM', 'ru').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final dateOnly = DateTime(date.year, date.month, date.day);
    final isToday = dateOnly == today;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : isDark
                  ? colorScheme.onSurface.withValues(alpha: 0.03)
                  : colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.3)
                : colorScheme.outline.withValues(alpha: 0.08),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [

            Container(
              width: 48,
              height: 48,
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary
                    : isToday
                        ? colorScheme.primary.withValues(alpha: 0.15)
                        : colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
                border: isToday && !isSelected
                    ? Border.all(color: colorScheme.primary, width: 2)
                    : null,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    date.day.toString(),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onPrimary
                          : isToday
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                      height: 1,
                    ),
                  ),
                  Text(
                    DateFormat.E('ru').format(date).toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.onPrimary.withValues(alpha: 0.8)
                          : isToday
                              ? colorScheme.primary.withValues(alpha: 0.8)
                              : colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),

            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _formatDate(date, l10n),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${items.length} ${_getTasksWord(items.length, l10n)}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: isSelected
                  ? colorScheme.primary
                  : colorScheme.onSurface.withValues(alpha: 0.3),
            ),
          ],
        ),
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