import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'timer_progress_widget.dart';

class BreakCard extends StatelessWidget {
  final String start;
  final String end;
  final int duration;

  const BreakCard({
    super.key,
    required this.start,
    required this.end,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.tertiaryContainer,
            colorScheme.surfaceContainerHighest,
          ],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.surface.withValues(alpha: 0.5),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.free_breakfast_rounded,
                  size: 18,
                  color: colorScheme.tertiary,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Text(
                  l10n.breakDuration(duration),
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TimerProgressWidget(
            startTime: start,
            endTime: end,
            color: colorScheme.tertiary,
            label: l10n.breakLabel,
            isBreak: true,
            textStyle: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onTertiaryContainer,
            ),
          ),
        ],
      ),
    );
  }
}