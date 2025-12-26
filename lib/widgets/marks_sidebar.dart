import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../viewmodels/marks_viewmodel.dart';
import '../providers/grading_provider.dart';

class MarksSidebar extends StatelessWidget {
  final List<SubjectData> subjects;
  final String? selectedSubjectId;
  final ValueChanged<SubjectData> onSelectSubject;
  final PeriodSelectionItem? selectedPeriod;
  final List<PeriodSelectionItem> allPeriods;
  final ValueChanged<PeriodSelectionItem> onSelectPeriod;
  final DateTime? lastUpdated;
  final bool isRefreshing;
  final VoidCallback onRefresh;

  const MarksSidebar({
    super.key,
    required this.subjects,
    required this.selectedSubjectId,
    required this.onSelectSubject,
    required this.selectedPeriod,
    required this.allPeriods,
    required this.onSelectPeriod,
    required this.lastUpdated,
    required this.isRefreshing,
    required this.onRefresh,
  });

  String _formatLastUpdated(DateTime? time, AppLocalizations l10n) {
    if (time == null) return "";
    final now = DateTime.now();
    final diff = now.difference(time);
    final isRu = l10n.locale.languageCode == 'ru';

    if (diff.inMinutes < 1) return isRu ? "только что" : "just now";
    if (diff.inMinutes < 60) {
      return "${diff.inMinutes} ${isRu ? 'мин назад' : 'min ago'}";
    }
    if (diff.inHours < 24) {
      return "${diff.inHours} ${isRu ? 'ч назад' : 'h ago'}";
    }
    if (diff.inDays == 1) return isRu ? "вчера" : "yesterday";
    return "${diff.inDays} ${isRu ? 'дн назад' : 'd ago'}";
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final grading = context.watch<GradingProvider>();

    return Container(
      width: 340,
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

          if (allPeriods.isNotEmpty)
            _buildPeriodSelector(context, colorScheme, isDark, l10n),

          _buildStatsRow(context, colorScheme, grading, l10n),

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
                  l10n.subjects.toUpperCase(),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                  ),
                ),
                const Spacer(),
                Text(
                  '${subjects.length}',
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 8),

          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: subjects.length,
              itemBuilder: (context, index) {
                final subject = subjects[index];
                final isSelected = subject.id == selectedSubjectId;
                return _SubjectListItem(
                  subject: subject,
                  isSelected: isSelected,
                  onTap: () => onSelectSubject(subject),
                  grading: grading,
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(
      BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 12, 12),
      child: Row(
        children: [
          Text(
            l10n.marks,
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),

          _buildRefreshButton(context, colorScheme, l10n),
        ],
      ),
    );
  }

  Widget _buildRefreshButton(
      BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    return Tooltip(
      message: l10n.updateMarks,
      child: GestureDetector(
        onTap: isRefreshing ? null : onRefresh,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primary.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: isRefreshing
              ? Padding(
                  padding: const EdgeInsets.all(10),
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              : Icon(
                  Icons.refresh_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
        ),
      ),
    );
  }

  Widget _buildPeriodSelector(
      BuildContext context, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          _showPeriodPicker(context, colorScheme, l10n);
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
                  Icons.calendar_month_rounded,
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
                      selectedPeriod?.displayName ?? l10n.selectPeriod,
                      style: GoogleFonts.inter(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
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

  Widget _buildStatsRow(BuildContext context, ColorScheme colorScheme,
      GradingProvider grading, AppLocalizations l10n) {
    double totalAvg = 0;
    int count = 0;
    for (var subject in subjects) {
      final avg = double.tryParse(subject.average);
      if (avg != null && avg > 0) {
        totalAvg += avg;
        count++;
      }
    }
    final overallAvg = count > 0 ? (totalAvg / count) : 0.0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
      child: Row(
        children: [

          if (overallAvg > 0)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: grading.getAverageColor(overallAvg),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.trending_up_rounded,
                    size: 16,
                    color: Colors.white,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    overallAvg.toStringAsFixed(2),
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          const Spacer(),

          if (lastUpdated != null)
            Text(
              _formatLastUpdated(lastUpdated, l10n),
              style: GoogleFonts.inter(
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
        ],
      ),
    );
  }

  void _showPeriodPicker(
      BuildContext context, ColorScheme colorScheme, AppLocalizations l10n) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.onSurface.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    l10n.selectPeriod,
                    style: GoogleFonts.inter(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ...allPeriods.map((period) {
                    final isSelected = selectedPeriod == period;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onSelectPeriod(period);
                          Navigator.pop(ctx);
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
                                  style: GoogleFonts.inter(
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
                  }),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SubjectListItem extends StatelessWidget {
  final SubjectData subject;
  final bool isSelected;
  final VoidCallback onTap;
  final GradingProvider grading;

  const _SubjectListItem({
    required this.subject,
    required this.isSelected,
    required this.onTap,
    required this.grading,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final avgColor = grading.getAverageColorFromString(subject.average);
    final hasMarks = subject.marks.isNotEmpty;

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
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: hasMarks
                    ? avgColor.withValues(alpha: 0.15)
                    : colorScheme.onSurface.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  subject.average != "-" ? subject.average : "—",
                  style: GoogleFonts.inter(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: hasMarks
                        ? avgColor
                        : colorScheme.onSurface.withValues(alpha: 0.3),
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
                    subject.name,
                    style: GoogleFonts.inter(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.primary
                          : colorScheme.onSurface,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasMarks
                        ? '${subject.marks.length} ${_getMarksWord(subject.marks.length, context)}'
                        : '—',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),

            if (subject.totalMark != null)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: grading
                      .getAverageColorFromString(subject.totalMark!)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.verified_outlined,
                      size: 12,
                      color: grading.getAverageColorFromString(subject.totalMark!),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      subject.totalMark!,
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color:
                            grading.getAverageColorFromString(subject.totalMark!),
                      ),
                    ),
                  ],
                ),
              )
            else
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

  String _getMarksWord(int count, BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isRu = l10n.locale.languageCode == 'ru';
    if (!isRu) return count == 1 ? 'mark' : 'marks';

    final mod10 = count % 10;
    final mod100 = count % 100;

    if (mod10 == 1 && mod100 != 11) return 'оценка';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'оценки';
    }
    return 'оценок';
  }
}