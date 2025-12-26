import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

class WeekStrip extends StatelessWidget {
  final List<DateTime> week;
  final DateTime selectedDate;
  final ValueChanged<DateTime> onSelect;

  const WeekStrip({
    super.key,
    required this.week,
    required this.selectedDate,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: week.map((date) {
          final isSelected = isSameDay(date, selectedDate);
          final isToday = isSameDay(date, DateTime.now());

          return GestureDetector(
            onTap: () {
              HapticFeedback.selectionClick();
              onSelect(date);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 44,
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    DateFormat.E('ru').format(date).toUpperCase(),
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.5,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? colorScheme.primary
                          : isToday
                              ? colorScheme.primary.withValues(alpha: 0.1)
                              : Colors.transparent,
                      border: isToday && !isSelected
                          ? Border.all(
                              color: colorScheme.primary,
                              width: 2,
                            )
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      date.day.toString(),
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: isSelected
                            ? colorScheme.onPrimary
                            : isToday
                                ? colorScheme.primary
                                : colorScheme.onSurface,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }).toList(),
      ),
    );
  }

  bool isSameDay(DateTime a, DateTime b) {
    return a.year == b.year && a.month == b.month && a.day == b.day;
  }
}