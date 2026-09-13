import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/app_font.dart';
import '../viewmodels/marks_viewmodel.dart';

/// периоды, объединённые в блоки по учебному году и классу
class PeriodPickerList extends StatelessWidget {
  final List<PeriodSelectionItem> periods;
  final PeriodSelectionItem? selectedPeriod;
  final ValueChanged<PeriodSelectionItem> onSelect;

  const PeriodPickerList({
    super.key,
    required this.periods,
    required this.selectedPeriod,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final groups = <(int, String), List<PeriodSelectionItem>>{};
    for (final period in periods) {
      final key = (period.groupId, period.contextLabel);
      groups.putIfAbsent(key, () => []).add(period);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (index, group) in groups.values.indexed) ...[
          if (index > 0) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colorScheme.outline.withValues(alpha: 0.15),
            ),
            const SizedBox(height: 20),
          ],
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              group.first.contextLabel,
              style: appFont(context,
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ),
          for (final period in group) _buildPeriod(context, period, colorScheme),
        ],
      ],
    );
  }

  Widget _buildPeriod(BuildContext context, PeriodSelectionItem period, ColorScheme colorScheme) {
    final isSelected = selectedPeriod == period;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          onSelect(period);
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isSelected
                ? colorScheme.primary.withValues(alpha: 0.1)
                : colorScheme.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected
                  ? colorScheme.primary.withValues(alpha: 0.3)
                  : colorScheme.outline.withValues(alpha: 0.08),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  period.displayName,
                  style: appFont(context,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: isSelected
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                ),
              ),
              if (isSelected)
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
