import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../models/lesson_view_model.dart';

class DiarySidebar extends StatelessWidget {
  final DateTime selectedDate;
  final List<DateTime> currentWeek;
  final ValueChanged<DateTime> onSelectDate;
  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;
  final List<LessonViewModel> Function(DateTime) getLessonsForDate;

  const DiarySidebar({
    super.key,
    required this.selectedDate,
    required this.currentWeek,
    required this.onSelectDate,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.getLessonsForDate,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      width: 320,
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surface
            : colorScheme.surfaceContainerLowest,
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

          _buildMiniCalendar(context, colorScheme),

          const SizedBox(height: 8),

          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20),
            height: 1,
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),

          const SizedBox(height: 16),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  l10n.weekSchedule,
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const Spacer(),
                _buildWeekNavButton(
                  icon: Icons.chevron_left_rounded,
                  onTap: onPreviousWeek,
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 4),
                _buildWeekNavButton(
                  icon: Icons.chevron_right_rounded,
                  onTap: onNextWeek,
                  colorScheme: colorScheme,
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: currentWeek.length,
              itemBuilder: (context, index) {
                final date = currentWeek[index];
                final lessons = getLessonsForDate(date);
                return _DayPreviewCard(
                  date: date,
                  isSelected: _isSameDay(date, selectedDate),
                  lessons: lessons,
                  onTap: () => onSelectDate(date),
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
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () async {
                HapticFeedback.lightImpact();
                final picked = await showDatePicker(
                  context: context,
                  initialDate: selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                  builder: (context, child) {
                    return Theme(
                      data: Theme.of(context).copyWith(
                        colorScheme: colorScheme,
                      ),
                      child: child!,
                    );
                  },
                );
                if (picked != null) {
                  onSelectDate(picked);
                }
              },
              child: Row(
                children: [
                  Text(
                    DateFormat('LLLL yyyy', 'ru').format(selectedDate),
                    style: GoogleFonts.outfit(
                      fontSize: 22,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          _buildIconButton(
            icon: Icons.today_rounded,
            onTap: () {
              HapticFeedback.lightImpact();
              onSelectDate(DateTime.now());
            },
            colorScheme: colorScheme,
            tooltip: l10n.today,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniCalendar(BuildContext context, ColorScheme colorScheme) {
    final firstOfMonth = DateTime(selectedDate.year, selectedDate.month, 1);
    final lastOfMonth = DateTime(selectedDate.year, selectedDate.month + 1, 0);

    int startWeekday = firstOfMonth.weekday - 1;
    final daysInMonth = lastOfMonth.day;

    final weekDays = ['ПН', 'ВТ', 'СР', 'ЧТ', 'ПТ', 'СБ', 'ВС'];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        children: [

          Row(
            children: weekDays.map((day) {
              final isWeekend = day == 'СБ' || day == 'ВС';
              return Expanded(
                child: Center(
                  child: Text(
                    day,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: isWeekend
                          ? colorScheme.error.withValues(alpha: 0.6)
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),

          ...List.generate(6, (weekIndex) {
            return Row(
              children: List.generate(7, (dayIndex) {
                final dayNumber = weekIndex * 7 + dayIndex - startWeekday + 1;
                if (dayNumber < 1 || dayNumber > daysInMonth) {
                  return const Expanded(child: SizedBox(height: 32));
                }

                final date = DateTime(selectedDate.year, selectedDate.month, dayNumber);
                final isSelected = _isSameDay(date, selectedDate);
                final isToday = _isSameDay(date, DateTime.now());
                final isWeekend = dayIndex >= 5;

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onSelectDate(date);
                    },
                    child: Container(
                      height: 32,
                      margin: const EdgeInsets.all(1),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colorScheme.primary
                            : isToday
                                ? colorScheme.primary.withValues(alpha: 0.1)
                                : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                        border: isToday && !isSelected
                            ? Border.all(
                                color: colorScheme.primary,
                                width: 1.5,
                              )
                            : null,
                      ),
                      child: Center(
                        child: Text(
                          dayNumber.toString(),
                          style: GoogleFonts.inter(
                            fontSize: 13,
                            fontWeight: isSelected || isToday
                                ? FontWeight.w600
                                : FontWeight.w500,
                            color: isSelected
                                ? colorScheme.onPrimary
                                : isToday
                                    ? colorScheme.primary
                                    : isWeekend
                                        ? colorScheme.error.withValues(alpha: 0.7)
                                        : colorScheme.onSurface.withValues(alpha: 0.8),
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
            );
          }),
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
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 18,
          color: colorScheme.primary,
        ),
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
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(
            icon,
            size: 20,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DayPreviewCard extends StatelessWidget {
  final DateTime date;
  final bool isSelected;
  final List<LessonViewModel> lessons;
  final VoidCallback onTap;

  const _DayPreviewCard({
    required this.date,
    required this.isSelected,
    required this.lessons,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isToday = _isSameDay(date, DateTime.now());
    final l10n = AppLocalizations.of(context)!;

    final realLessons = lessons.where((l) => !l.isPlaceholder).toList();
    final hasLessons = realLessons.isNotEmpty;

    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.only(bottom: 8),
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
                  if (!hasLessons)
                    Text(
                      l10n.noLessons,
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontStyle: FontStyle.italic,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    )
                  else ...[
                    Text(
                      l10n.lessonsCount(realLessons.length),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? colorScheme.primary
                            : colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      realLessons.take(3).map((l) => l.subject).join(' • '),
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (realLessons.first.startTime.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        '${realLessons.first.startTime} — ${realLessons.last.endTime}',
                        style: GoogleFonts.inter(
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                  ],
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

  bool _isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}