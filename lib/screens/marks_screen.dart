import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../l10n/app_localizations.dart';
import '../viewmodels/marks_viewmodel.dart';
import '../providers/bell_schedule_provider.dart';
import '../providers/grading_provider.dart';
import '../widgets/lesson_card.dart';
import '../widgets/responsive_layout.dart';
import '../widgets/marks_sidebar.dart';

class MarksScreen extends StatelessWidget {
  const MarksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => MarksViewModel(
        Provider.of<BellScheduleProvider>(context, listen: false),
      )..loadPeriods(),
      child: const _MarksView(),
    );
  }
}

class _MarksView extends StatefulWidget {
  const _MarksView();

  @override
  State<_MarksView> createState() => _MarksViewState();
}

class _MarksViewState extends State<_MarksView>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  String? _selectedSubjectId;

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
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  void _dismissKeyboard() {
    FocusScope.of(context).unfocus();
  }

  String _formatLastUpdated(DateTime? time, AppLocalizations l10n) {
    if (time == null) return "";
    final now = DateTime.now();
    final diff = now.difference(time);
    final isRu = l10n.locale.languageCode == 'ru';

    if (diff.inMinutes < 1) return isRu ? "только что" : "just now";
    if (diff.inMinutes < 60) return "${diff.inMinutes} ${isRu ? 'мин назад' : 'min ago'}";
    if (diff.inHours < 24) return "${diff.inHours} ${isRu ? 'ч назад' : 'h ago'}";
    if (diff.inDays == 1) return isRu ? "вчера" : "yesterday";
    return "${diff.inDays} ${isRu ? 'дн назад' : 'd ago'}";
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MarksViewModel>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;

    if (isDesktop(context) && _selectedSubjectId == null && vm.subjects.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _selectedSubjectId = vm.subjects.first.id;
          });
        }
      });
    }

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SafeArea(
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: ResponsiveLayout(
              mobile: _buildMobileLayout(vm, colorScheme, isDark, l10n),
              desktop: _buildDesktopLayout(vm, colorScheme, isDark, l10n),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMobileLayout(
      MarksViewModel vm, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        _buildHeader(vm, colorScheme, l10n),

        if (vm.allPeriods.isNotEmpty)
          _buildPeriodSelector(vm, colorScheme, isDark, l10n),

        if (vm.selectedPeriod != null && !vm.isLoading)
          _buildRefreshButton(vm, colorScheme, isDark, l10n),

        Expanded(child: _buildContent(vm, colorScheme, isDark, l10n)),
      ],
    );
  }

  Widget _buildDesktopLayout(
      MarksViewModel vm, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    if (vm.isLoading && vm.subjects.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loadingMarks,
              style: GoogleFonts.inter(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (vm.error != null && vm.subjects.isEmpty) {
      return _buildErrorState(vm, colorScheme, l10n);
    }

    return Row(
      children: [

        MarksSidebar(
          subjects: vm.subjects,
          selectedSubjectId: _selectedSubjectId,
          onSelectSubject: (subject) {
            setState(() {
              _selectedSubjectId = subject.id;
            });
          },
          selectedPeriod: vm.selectedPeriod,
          allPeriods: vm.allPeriods,
          onSelectPeriod: (period) {
            vm.selectPeriod(period);

            setState(() {
              _selectedSubjectId = null;
            });
          },
          lastUpdated: vm.lastUpdated,
          isRefreshing: vm.isRefreshing,
          onRefresh: () => vm.refreshMarksData(),
        ),

        Expanded(
          child: _buildDesktopSubjectDetail(vm, colorScheme, isDark, l10n),
        ),
      ],
    );
  }

  Widget _buildDesktopSubjectDetail(
      MarksViewModel vm, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    if (vm.subjects.isEmpty) {
      return _buildEmptyState(colorScheme, l10n);
    }

    final selectedSubject = vm.subjects.firstWhere(
      (s) => s.id == _selectedSubjectId,
      orElse: () => vm.subjects.first,
    );

    return _DesktopSubjectDetail(
      subject: selectedSubject,
      vm: vm,
      l10n: l10n,
    );
  }

  Widget _buildHeader(MarksViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
      child: Row(
        children: [
          Text(
            l10n.marks,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
          const Spacer(),
          if (vm.lastUpdated != null && !vm.isLoading)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _formatLastUpdated(vm.lastUpdated, l10n),
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPeriodSelector(
      MarksViewModel vm, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            _showPeriodPicker(vm, colorScheme, l10n);
          },
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
                    Icons.calendar_month_rounded,
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
                        l10n.period,
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        vm.selectedPeriod?.displayName ?? l10n.selectPeriod,
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
                  Icons.keyboard_arrow_down_rounded,
                  color: colorScheme.onSurface.withValues(alpha: 0.3),
                  size: 24,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRefreshButton(
      MarksViewModel vm, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: GestureDetector(
        onTap: vm.isRefreshing
            ? null
            : () {
                HapticFeedback.lightImpact();
                vm.refreshMarksData();
              },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: isDark
                ? colorScheme.onSurface.withValues(alpha: 0.05)
                : colorScheme.onSurface.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: colorScheme.outline.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              if (vm.isRefreshing)
                SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.primary,
                  ),
                )
              else
                Icon(
                  Icons.refresh_rounded,
                  size: 18,
                  color: colorScheme.primary,
                ),
              const SizedBox(width: 10),
              Text(
                vm.isRefreshing ? l10n.updating : l10n.updateMarks,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent(
      MarksViewModel vm, ColorScheme colorScheme, bool isDark, AppLocalizations l10n) {
    if (vm.isLoading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              l10n.loadingMarks,
              style: GoogleFonts.inter(
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      );
    }

    if (vm.error != null) {
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
                style: GoogleFonts.inter(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                vm.error!,
                style: GoogleFonts.inter(
                  fontSize: 14,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: () => vm.loadPeriods(),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(l10n.retry, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
              ),
            ],
          ),
        ),
      );
    }

    if (vm.subjects.isEmpty) {
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
                Icons.grade_outlined,
                size: 40,
                color: colorScheme.primary.withValues(alpha: 0.5),
              ),
            ),
            const SizedBox(height: 20),
            Text(
              l10n.noMarks,
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.noMarksInPeriod,
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => vm.refreshMarksData(),
      color: colorScheme.primary,
      child: ListView.builder(
        keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
        padding: const EdgeInsets.only(bottom: 20, top: 4),
        itemCount: vm.subjects.length,
        itemBuilder: (context, index) {
          final subject = vm.subjects[index];
          return _SubjectCard(subject: subject, l10n: l10n);
        },
      ),
    );
  }

  void _showPeriodPicker(MarksViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
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
                  ...vm.allPeriods.map((period) {
                    final isSelected = vm.selectedPeriod == period;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          vm.selectPeriod(period);
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
              Icons.grade_outlined,
              size: 40,
              color: colorScheme.primary.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            l10n.noMarks,
            style: GoogleFonts.inter(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l10n.noMarksInPeriod,
            style: GoogleFonts.inter(
              fontSize: 14,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(MarksViewModel vm, ColorScheme colorScheme, AppLocalizations l10n) {
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
              style: GoogleFonts.inter(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              vm.error ?? '',
              style: GoogleFonts.inter(
                fontSize: 14,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => vm.loadPeriods(),
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(l10n.retry, style: GoogleFonts.inter(fontWeight: FontWeight.w500)),
            ),
          ],
        ),
      ),
    );
  }
}

class _DesktopSubjectDetail extends StatelessWidget {
  final SubjectData subject;
  final MarksViewModel vm;
  final AppLocalizations l10n;

  const _DesktopSubjectDetail({
    required this.subject,
    required this.vm,
    required this.l10n,
  });

  Color _getMarkColor(String mark) {
    switch (mark.replaceAll('+', '').replaceAll('-', '')) {
      case '5':
        return const Color(0xFF22C55E);
      case '4':
        return const Color(0xFF3B82F6);
      case '3':
        return const Color(0xFFF59E0B);
      case '2':
      case '1':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final grading = context.watch<GradingProvider>();

    final hasChanges = vm.hasChanges(subject.id);
    final modifiedAvg = vm.calculateModifiedAverage(subject.id);
    final virtualMarks = vm.getVirtualMarks(subject.id);

    final Map<DateTime, List<MarkData>> grouped = {};
    for (var m in subject.marks) {
      final markId = '${subject.id}_${m.date.millisecondsSinceEpoch}_${m.value}';
      if (vm.isMarkDeleted(markId)) continue;

      final day = DateTime(m.date.year, m.date.month, m.date.day);
      if (!grouped.containsKey(day)) grouped[day] = [];
      grouped[day]!.add(m);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

    String resolveBaseAverage() {
      if (hasChanges && modifiedAvg != "-") return modifiedAvg;
      if (subject.average != "-") return subject.average;
      return subject.calculatedAverage;
    }

    final baseAverage = resolveBaseAverage();
    final baseAverageValue = double.tryParse(baseAverage);
    final predictedGrade = grading.showPredictedGrade &&
            baseAverage != "-" &&
            (baseAverageValue ?? 0) > 0
        ? grading.getPredictedGrade(baseAverage)
        : null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [

        _buildHeader(context, colorScheme, grading, baseAverage, predictedGrade),

        _buildStatsCards(context, colorScheme, isDark, grading, predictedGrade, hasChanges, modifiedAvg),

        Expanded(
          child: _buildMarksSection(
            context,
            colorScheme,
            isDark,
            grouped,
            sortedDates,
            virtualMarks,
            hasChanges,
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context, ColorScheme colorScheme,
      GradingProvider grading, String baseAverage, String? predictedGrade) {
    final avgColor = grading.getAverageColorFromString(baseAverage);

    return Container(
      padding: const EdgeInsets.fromLTRB(32, 28, 32, 20),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outline.withValues(alpha: 0.08),
          ),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  subject.name,
                  style: GoogleFonts.outfit(
                    fontSize: 28,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                if (subject.teacher != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.person_outline_rounded,
                        size: 16,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        subject.teacher!,
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),

          if (baseAverage != "-")
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              decoration: BoxDecoration(
                color: avgColor,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: avgColor.withValues(alpha: 0.3),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                children: [
                  Text(
                    baseAverage,
                    style: GoogleFonts.outfit(
                      fontSize: 32,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    l10n.averageScore,
                    style: GoogleFonts.inter(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildStatsCards(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
    GradingProvider grading,
    String? predictedGrade,
    bool hasChanges,
    String modifiedAvg,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 20, 32, 0),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [

          if (subject.totalMark != null)
            _StatCard(
              icon: Icons.verified_outlined,
              label: l10n.finalMark,
              value: subject.totalMark!,
              color: grading.getAverageColorFromString(subject.totalMark!),
              colorScheme: colorScheme,
              isDark: isDark,
            ),

          if (predictedGrade != null)
            _StatCard(
              icon: Icons.flag_rounded,
              label: l10n.prediction,
              value: predictedGrade,
              color: colorScheme.primary,
              colorScheme: colorScheme,
              isDark: isDark,
            ),

          if (subject.rating != null)
            _StatCard(
              icon: Icons.bar_chart_rounded,
              label: l10n.rating,
              value: subject.rating!,
              color: colorScheme.tertiary,
              colorScheme: colorScheme,
              isDark: isDark,
            ),

          if (hasChanges && modifiedAvg != "-")
            _StatCard(
              icon: Icons.edit_note_rounded,
              label: l10n.modifiedAverage,
              value: modifiedAvg,
              color: grading.getAverageColorFromString(modifiedAvg),
              colorScheme: colorScheme,
              isDark: isDark,
            ),

          _StatCard(
            icon: Icons.format_list_numbered_rounded,
            label: l10n.marksCount,
            value: subject.marks.length.toString(),
            color: colorScheme.secondary,
            colorScheme: colorScheme,
            isDark: isDark,
          ),
        ],
      ),
    );
  }

  Widget _buildMarksSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
    Map<DateTime, List<MarkData>> grouped,
    List<DateTime> sortedDates,
    List<VirtualMark> virtualMarks,
    bool hasChanges,
  ) {
    return ListView(
      padding: const EdgeInsets.all(32),
      children: [

        Row(
          children: [
            Text(
              l10n.allMarks.toUpperCase(),
              style: GoogleFonts.inter(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.8,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const Spacer(),

            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                _showAddMarkDialog(context, vm, subject.id);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.add_rounded,
                      size: 16,
                      color: colorScheme.primary,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.addMark,
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

            if (hasChanges) ...[
              const SizedBox(width: 8),
              GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  vm.resetAllChanges(subject.id);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: colorScheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.refresh_rounded,
                        size: 16,
                        color: colorScheme.error,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        l10n.resetChanges,
                        style: GoogleFonts.inter(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),

        const SizedBox(height: 20),

        if (virtualMarks.isNotEmpty) ...[
          _buildVirtualMarksRow(context, colorScheme, isDark, virtualMarks),
          const SizedBox(height: 24),
        ],

        if (sortedDates.isEmpty && virtualMarks.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: Text(
                l10n.noMarks,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
              ),
            ),
          )
        else
          ...sortedDates.map((date) {
            final marks = grouped[date]!;
            return _MarkDateRow(
              date: date,
              marks: marks,
              subjectId: subject.id,
              vm: vm,
              l10n: l10n,
              getMarkColor: _getMarkColor,
            );
          }),
      ],
    );
  }

  Widget _buildVirtualMarksRow(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
    List<VirtualMark> virtualMarks,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.edit_note_rounded,
                size: 18,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.virtualMarks,
                style: GoogleFonts.inter(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: virtualMarks.map((mark) {
              return GestureDetector(
                onTap: () {
                  HapticFeedback.lightImpact();
                  _showEditVirtualMarkDialog(context, vm, subject.id, mark);
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _getMarkColor(mark.value).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _getMarkColor(mark.value).withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        mark.value,
                        style: GoogleFonts.inter(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: _getMarkColor(mark.value),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'x${mark.weight.toStringAsFixed(mark.weight == mark.weight.roundToDouble() ? 0 : 1)}',
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  void _showAddMarkDialog(BuildContext context, MarksViewModel vm, String subjectId) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => _AddEditMarkDialog(
        subjectId: subjectId,
        vm: vm,
        l10n: l10n,
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _showEditVirtualMarkDialog(
      BuildContext context, MarksViewModel vm, String subjectId, VirtualMark mark) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => _AddEditMarkDialog(
        subjectId: subjectId,
        vm: vm,
        l10n: l10n,
        existingMark: mark,
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;
  final ColorScheme colorScheme;
  final bool isDark;

  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.colorScheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: color),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
              Text(
                value,
                style: GoogleFonts.inter(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MarkDateRow extends StatelessWidget {
  final DateTime date;
  final List<MarkData> marks;
  final String subjectId;
  final MarksViewModel vm;
  final AppLocalizations l10n;
  final Color Function(String) getMarkColor;

  const _MarkDateRow({
    required this.date,
    required this.marks,
    required this.subjectId,
    required this.vm,
    required this.l10n,
    required this.getMarkColor,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.03)
            : colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Container(
            width: 50,
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(
              children: [
                Text(
                  date.day.toString(),
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                    height: 1,
                  ),
                ),
                Text(
                  DateFormat.MMM('ru').format(date),
                  style: GoogleFonts.inter(
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),

          Expanded(
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: marks.map((mark) {
                final markId =
                    '${subjectId}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
                return GestureDetector(
                  onTap: () {
                    HapticFeedback.lightImpact();
                    showDialog(
                      context: context,
                      builder: (context) => Dialog(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 500),
                          child: LessonDetailSheet(lesson: mark.lesson, lessonDate: mark.date),
                        ),
                      ),
                    );
                  },
                  onLongPress: () {
                    HapticFeedback.heavyImpact();
                    _showMarkOptions(context, vm, subjectId, mark, markId);
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: getMarkColor(mark.value).withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: getMarkColor(mark.value).withValues(alpha: 0.3),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          mark.value,
                          style: GoogleFonts.inter(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: getMarkColor(mark.value),
                          ),
                        ),
                        if (mark.lesson.markWeight != null &&
                            mark.lesson.markWeight != 1.0) ...[
                          const SizedBox(width: 6),
                          Text(
                            'x${mark.lesson.markWeight!.toStringAsFixed(mark.lesson.markWeight! == mark.lesson.markWeight!.roundToDouble() ? 0 : 1)}',
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  void _showMarkOptions(
    BuildContext context,
    MarksViewModel vm,
    String subjectId,
    MarkData mark,
    String markId,
  ) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '${l10n.markCaps} ${mark.value}',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(Icons.visibility_off_outlined, color: colorScheme.error),
              title: Text(l10n.excludeFromCalc),
              subtitle: Text(l10n.markNotCounted),
              onTap: () {
                Navigator.pop(ctx);
                vm.deleteOriginalMark(markId);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.markExcludedMessage(mark.value)),
                    behavior: SnackBarBehavior.floating,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    action: SnackBarAction(
                      label: l10n.cancel,
                      onPressed: () => vm.restoreOriginalMark(markId),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.cancel),
          ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  final SubjectData subject;
  final AppLocalizations l10n;

  const _SubjectCard({required this.subject, required this.l10n});

  Color _getMarkColor(String mark) {
    switch (mark.replaceAll('+', '').replaceAll('-', '')) {
      case '5':
        return const Color(0xFF22C55E);
      case '4':
        return const Color(0xFF3B82F6);
      case '3':
        return const Color(0xFFF59E0B);
      case '2':
      case '1':
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vm = context.watch<MarksViewModel>();
    final grading = context.watch<GradingProvider>();

    final hasChanges = vm.hasChanges(subject.id);
    final modifiedAvg = vm.calculateModifiedAverage(subject.id);
    final virtualMarks = vm.getVirtualMarks(subject.id);

    final Map<DateTime, List<MarkData>> grouped = {};
    for (var m in subject.marks) {
      final markId = '${subject.id}_${m.date.millisecondsSinceEpoch}_${m.value}';
      if (vm.isMarkDeleted(markId)) continue;

      final day = DateTime(m.date.year, m.date.month, m.date.day);
      if (!grouped.containsKey(day)) grouped[day] = [];
      grouped[day]!.add(m);
    }
    final sortedDates = grouped.keys.toList()..sort((a, b) => a.compareTo(b));

    String resolveBaseAverage() {
      if (hasChanges && modifiedAvg != "-") return modifiedAvg;
      if (subject.average != "-") return subject.average;
      return subject.calculatedAverage;
    }

    final baseAverage = resolveBaseAverage();
    final baseAverageValue = double.tryParse(baseAverage);
    final predictedGrade = grading.showPredictedGrade &&
            baseAverage != "-" &&
            (baseAverageValue ?? 0) > 0
        ? grading.getPredictedGrade(baseAverage)
        : null;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            HapticFeedback.lightImpact();
            showModalBottomSheet(
              context: context,
              isScrollControlled: true,
              backgroundColor: Colors.transparent,
              builder: (ctx) => ChangeNotifierProvider.value(
                value: vm,
                child: _SubjectDetailSheet(subject: subject, l10n: l10n),
              ),
            );
          },
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Row(
                  children: [
                    Expanded(
                      child: Text(
                        subject.name,
                        style: GoogleFonts.inter(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 12),
                    _buildAverageBadges(context, grading, hasChanges, modifiedAvg,
                        predictedGrade, colorScheme),
                  ],
                ),

                if (subject.marks.isNotEmpty || virtualMarks.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [

                        ...sortedDates.map((date) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Column(
                              children: [
                                ...grouped[date]!.map((mark) {
                                  final markId =
                                      '${subject.id}_${mark.date.millisecondsSinceEpoch}_${mark.value}';
                                  return Padding(
                                    padding: const EdgeInsets.only(bottom: 4),
                                    child: GestureDetector(
                                      onTap: () {
                                        HapticFeedback.lightImpact();
                                        showModalBottomSheet(
                                          context: context,
                                          isScrollControlled: true,
                                          backgroundColor: Colors.transparent,
                                          builder: (context) =>
                                              LessonDetailSheet(lesson: mark.lesson, lessonDate: mark.date),
                                        );
                                      },
                                      onLongPress: () {
                                        HapticFeedback.heavyImpact();
                                        _onMarkLongPress(context, vm, subject.id, mark, markId);
                                      },
                                      child: _MarkBadge(
                                        value: mark.value,
                                        color: _getMarkColor(mark.value),
                                      ),
                                    ),
                                  );
                                }),
                                const SizedBox(height: 2),
                                Text(
                                  DateFormat('d.MM', 'ru').format(date),
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: colorScheme.onSurface.withValues(alpha: 0.4),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        ...virtualMarks.map((mark) {
                          return Padding(
                            padding: const EdgeInsets.only(right: 10),
                            child: Column(
                              children: [
                                GestureDetector(
                                  onTap: () {
                                    HapticFeedback.lightImpact();
                                    _showEditVirtualMarkDialog(context, vm, subject.id, mark);
                                  },
                                  child: _MarkBadge(
                                    value: mark.value,
                                    color: _getMarkColor(mark.value),
                                    isVirtual: true,
                                  ),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  'x${mark.weight.toStringAsFixed(mark.weight == mark.weight.roundToDouble() ? 0 : 1)}',
                                  style: GoogleFonts.inter(
                                    fontSize: 10,
                                    color: colorScheme.primary.withValues(alpha: 0.7),
                                  ),
                                ),
                              ],
                            ),
                          );
                        }),

                        Column(
                          children: [
                            GestureDetector(
                              onTap: () {
                                HapticFeedback.lightImpact();
                                _showAddMarkDialog(context, vm, subject.id);
                              },
                              child: Container(
                                width: 34,
                                height: 34,
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: colorScheme.primary.withValues(alpha: 0.2),
                                  ),
                                ),
                                child: Icon(
                                  Icons.add_rounded,
                                  size: 18,
                                  color: colorScheme.primary,
                                ),
                              ),
                            ),
                            const SizedBox(height: 14),
                          ],
                        ),
                      ],
                    ),
                  ),
                ] else
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            l10n.noMarks,
                            style: GoogleFonts.inter(
                              fontSize: 13,
                              color: colorScheme.onSurface.withValues(alpha: 0.4),
                            ),
                          ),
                        ),
                        GestureDetector(
                          onTap: () {
                            HapticFeedback.lightImpact();
                            _showAddMarkDialog(context, vm, subject.id);
                          },
                          child: Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: colorScheme.primary.withValues(alpha: 0.2),
                              ),
                            ),
                            child: Icon(
                              Icons.add_rounded,
                              size: 18,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),

                if (hasChanges) ...[
                  const SizedBox(height: 12),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      vm.resetAllChanges(subject.id);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: colorScheme.error.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.refresh_rounded,
                            size: 14,
                            color: colorScheme.error,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            l10n.resetChanges,
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.error,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAverageBadges(
    BuildContext context,
    GradingProvider grading,
    bool hasChanges,
    String modifiedAvg,
    String? predictedGrade,
    ColorScheme colorScheme,
  ) {
    Color avgColor(String avg) => grading.getAverageColorFromString(avg);

    Color predictedColor() {
      if (predictedGrade == null) return avgColor(subject.average);
      if (predictedGrade.contains('-')) {
        final parts = predictedGrade.split('-');
        final g1 = int.tryParse(parts.first);
        final g2 = int.tryParse(parts.last);
        if (g1 != null && g2 != null) {
          final c1 = grading.getColorForGrade(g1);
          final c2 = grading.getColorForGrade(g2);
          return Color.lerp(c1, c2, 0.5) ?? c1;
        }
      }
      final single = int.tryParse(predictedGrade.replaceAll(RegExp(r'\D'), ''));
      if (single != null) return grading.getColorForGrade(single);
      return avgColor(subject.average);
    }

    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [

        if (subject.totalMark != null)
          _AverageBadge(
            value: subject.totalMark!,
            color: avgColor(subject.totalMark!),
            icon: Icons.verified_outlined,
          ),

        if (predictedGrade != null)
          _AverageBadge(
            value: predictedGrade,
            color: predictedColor(),
            icon: Icons.flag_rounded,
          ),

        if (hasChanges && modifiedAvg != "-")
          _AverageBadge(
            value: modifiedAvg,
            color: avgColor(modifiedAvg),
            icon: Icons.edit_rounded,
            isFilled: true,
          ),

        if (!hasChanges &&
            subject.calculatedAverage != "-" &&
            subject.calculatedAverage != subject.average)
          _AverageBadge(
            value: subject.calculatedAverage,
            color: avgColor(subject.calculatedAverage),
          ),

        if (subject.average != "-")
          _AverageBadge(
            value: subject.average,
            color: avgColor(subject.average),
            isFilled: true,
          ),
      ],
    );
  }

  void _showAddMarkDialog(BuildContext context, MarksViewModel vm, String subjectId) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => _AddEditMarkDialog(
        subjectId: subjectId,
        vm: vm,
        l10n: l10n,
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _showEditVirtualMarkDialog(
      BuildContext context, MarksViewModel vm, String subjectId, VirtualMark mark) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => _AddEditMarkDialog(
        subjectId: subjectId,
        vm: vm,
        l10n: l10n,
        existingMark: mark,
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }

  void _onMarkLongPress(
      BuildContext context, MarksViewModel vm, String subjectId, MarkData mark, String markId) {
    final colorScheme = Theme.of(context).colorScheme;

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
                  '${l10n.markCaps} ${mark.value}',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 16),
                _ActionTile(
                  icon: Icons.edit_note_rounded,
                  title: l10n.editMark,
                  subtitle: l10n.replaceWithAnother,
                  colorScheme: colorScheme,
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditOriginalMarkDialog(context, vm, subjectId, mark, markId);
                  },
                ),
                const SizedBox(height: 8),
                _ActionTile(
                  icon: Icons.visibility_off_outlined,
                  title: l10n.excludeFromCalc,
                  subtitle: l10n.markNotCounted,
                  colorScheme: colorScheme,
                  isDestructive: true,
                  onTap: () {
                    Navigator.pop(ctx);
                    vm.deleteOriginalMark(markId);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(l10n.markExcludedMessage(mark.value)),
                        behavior: SnackBarBehavior.floating,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        margin: const EdgeInsets.all(16),
                        action: SnackBarAction(
                          label: l10n.cancel,
                          onPressed: () => vm.restoreOriginalMark(markId),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEditOriginalMarkDialog(
    BuildContext context, MarksViewModel vm,
    String subjectId,
    MarkData mark,
    String markId,
  ) {
    final initialWeight = mark.lesson.markWeight ?? 1.0;
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: '',
      barrierColor: Colors.black54,
      transitionDuration: const Duration(milliseconds: 200),
      pageBuilder: (context, anim1, anim2) => _AddEditMarkDialog(
        subjectId: subjectId,
        vm: vm,
        l10n: l10n,
        initialValue: mark.value,
        initialWeight: initialWeight,
        onSave: (value, weight) {
          vm.deleteOriginalMark(markId);
          vm.addVirtualMark(subjectId, value, weight, date: mark.date);
        },
      ),
      transitionBuilder: (context, anim1, anim2, child) {
        return FadeTransition(
          opacity: anim1,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.95, end: 1.0).animate(
              CurvedAnimation(parent: anim1, curve: Curves.easeOutCubic),
            ),
            child: child,
          ),
        );
      },
    );
  }
}

class _MarkBadge extends StatelessWidget {
  final String value;
  final Color color;
  final bool isVirtual;

  const _MarkBadge({
    required this.value,
    required this.color,
    this.isVirtual = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: color.withValues(alpha: isVirtual ? 0.5 : 0.3),
          width: isVirtual ? 2 : 1.5,
          strokeAlign: BorderSide.strokeAlignInside,
        ),
      ),
      child: Center(
        child: Text(
          value,
          style: GoogleFonts.inter(
            fontSize: 14,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ),
    );
  }
}

class _AverageBadge extends StatelessWidget {
  final String value;
  final Color color;
  final IconData? icon;
  final bool isFilled;

  const _AverageBadge({
    required this.value,
    required this.color,
    this.icon,
    this.isFilled = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: isFilled ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
        border: isFilled ? null : Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 12,
              color: isFilled ? Colors.white : color,
            ),
            const SizedBox(width: 3),
          ],
          Text(
            value,
            style: GoogleFonts.inter(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: isFilled ? Colors.white : color,
            ),
          ),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;
  final VoidCallback onTap;
  final bool isDestructive;

  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.colorScheme,
    required this.onTap,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    final color = isDestructive ? colorScheme.error : colorScheme.primary;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: color.withValues(alpha: 0.15),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(icon, size: 20, color: color),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: GoogleFonts.inter(
                      fontSize: 13,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddEditMarkDialog extends StatefulWidget {
  final String subjectId;
  final MarksViewModel vm;
  final VirtualMark? existingMark;
  final String? initialValue;
  final double? initialWeight;
  final void Function(String value, double weight)? onSave;
  final AppLocalizations l10n;

  const _AddEditMarkDialog({
    required this.subjectId,
    required this.vm,
    this.existingMark,
    this.initialValue,
    this.initialWeight,
    this.onSave,
    required this.l10n,
  });

  @override
  State<_AddEditMarkDialog> createState() => _AddEditMarkDialogState();
}

class _AddEditMarkDialogState extends State<_AddEditMarkDialog>
    with SingleTickerProviderStateMixin {
  late String _selectedMark;
  late double _weight;
  final _weightController = TextEditingController();

  int? _expandedGrade;
  late AnimationController _animController;
  late Animation<double> _expandAnimation;

  static const List<int> _mainGrades = [5, 4, 3, 2, 1];

  @override
  void initState() {
    super.initState();
    _selectedMark = widget.initialValue ?? widget.existingMark?.value ?? '5';
    _weight = widget.initialWeight ?? widget.existingMark?.weight ?? 1.0;
    _weightController.text = _weight.toString();

    _animController = AnimationController(
      duration: const Duration(milliseconds: 250),
      vsync: this,
    );
    _expandAnimation = CurvedAnimation(
      parent: _animController,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _weightController.dispose();
    _animController.dispose();
    super.dispose();
  }

  Color _getMarkColor(int grade) {
    switch (grade) {
      case 5:
        return const Color(0xFF22C55E);
      case 4:
        return const Color(0xFF3B82F6);
      case 3:
        return const Color(0xFFF59E0B);
      case 2:
      case 1:
        return const Color(0xFFEF4444);
      default:
        return Colors.grey;
    }
  }

  List<String> _getVariants(int grade) {
    return ['$grade+', '$grade', '$grade-'];
  }

  int _getBaseGrade(String mark) {
    return int.tryParse(mark.replaceAll('+', '').replaceAll('-', '')) ?? 5;
  }

  void _toggleExpanded(int grade) {
    HapticFeedback.selectionClick();
    if (_expandedGrade == grade) {
      _animController.reverse().then((_) {
        setState(() => _expandedGrade = null);
      });
    } else {
      setState(() => _expandedGrade = grade);
      _animController.forward(from: 0);
    }
  }

  void _selectVariant(String variant) {
    HapticFeedback.selectionClick();
    setState(() {
      _selectedMark = variant;
      _expandedGrade = null;
    });
    _animController.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.existingMark != null;
    final selectedBase = _getBaseGrade(_selectedMark);
    final l10n = widget.l10n;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      behavior: HitTestBehavior.translucent,
      child: Stack(
        children: [

        if (_expandedGrade != null)
          AnimatedBuilder(
            animation: _expandAnimation,
            builder: (context, child) {
              return GestureDetector(
                onTap: () => _toggleExpanded(_expandedGrade!),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 3 * _expandAnimation.value,
                    sigmaY: 3 * _expandAnimation.value,
                  ),
                  child: Container(
                    color: Colors.black.withValues(alpha: 0.3 * _expandAnimation.value),
                  ),
                ),
              );
            },
          ),

        Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              margin: const EdgeInsets.all(24),
              constraints: const BoxConstraints(maxWidth: 360),
              decoration: BoxDecoration(
                color: colorScheme.surface,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [

                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            isEditing ? l10n.edit : l10n.addMark,
                            style: GoogleFonts.outfit(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isEditing)
                          GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              widget.vm.deleteVirtualMark(
                                  widget.subjectId, widget.existingMark!.id);
                              Navigator.pop(context);
                            },
                            child: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: colorScheme.error.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.delete_outline_rounded,
                                size: 20,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),

                    if (MediaQuery.of(context).viewInsets.bottom > 0) ...[
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: Container(
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surface
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
                            onPressed: () => FocusScope.of(context).unfocus(),
                          ),
                        ),
                      ),
                    ],

                    const SizedBox(height: 24),

                    Text(
                      l10n.markCaps,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: _mainGrades.map((grade) {
                        final isSelected = selectedBase == grade;
                        final isExpanded = _expandedGrade == grade;
                        final color = _getMarkColor(grade);

                        return GestureDetector(
                          onTap: () => _toggleExpanded(grade),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            width: 54,
                            height: 54,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? color.withValues(alpha: 0.15)
                                  : isExpanded
                                      ? color.withValues(alpha: 0.08)
                                      : isDark
                                          ? colorScheme.onSurface.withValues(alpha: 0.05)
                                          : colorScheme.onSurface.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(
                                color: isSelected
                                    ? color
                                    : colorScheme.outline.withValues(alpha: 0.1),
                                width: isSelected ? 2.5 : 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                grade.toString(),
                                style: GoogleFonts.outfit(
                                  fontSize: 22,
                                  fontWeight: FontWeight.w600,
                                  color: isSelected
                                      ? color
                                      : colorScheme.onSurface.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),

                    AnimatedBuilder(
                      animation: _expandAnimation,
                      builder: (context, child) {
                        if (_expandedGrade == null && _animController.value == 0) {
                          return const SizedBox.shrink();
                        }

                        final variants =
                            _expandedGrade != null ? _getVariants(_expandedGrade!) : <String>[];
                        final color =
                            _expandedGrade != null ? _getMarkColor(_expandedGrade!) : Colors.grey;

                        return ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: _expandAnimation.value,
                            child: Opacity(
                              opacity: _expandAnimation.value,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 16),
                                child: Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: color.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(14),
                                    border: Border.all(
                                      color: color.withValues(alpha: 0.15),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                    children: variants.map((variant) {
                                      final isVariantSelected = _selectedMark == variant;
                                      return GestureDetector(
                                        onTap: () => _selectVariant(variant),
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 150),
                                          width: 60,
                                          height: 52,
                                          decoration: BoxDecoration(
                                            color: isVariantSelected
                                                ? color.withValues(alpha: 0.15)
                                                : colorScheme.surface,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: isVariantSelected
                                                  ? color
                                                  : color.withValues(alpha: 0.2),
                                              width: isVariantSelected ? 2 : 1.5,
                                            ),
                                          ),
                                          child: Center(
                                            child: Text(
                                              variant,
                                              style: GoogleFonts.outfit(
                                                fontSize: 18,
                                                fontWeight: FontWeight.w600,
                                                color: isVariantSelected
                                                    ? color
                                                    : color.withValues(alpha: 0.7),
                                              ),
                                            ),
                                          ),
                                        ),
                                      );
                                    }).toList(),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),

                    Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Center(
                        child: Text(
                          'Выбрано: $_selectedMark',
                          style: GoogleFonts.inter(
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                            color: _getMarkColor(selectedBase),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    Text(
                      l10n.markWeightCaps,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.8,
                        color: colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                    const SizedBox(height: 12),

                    Row(
                      children: [
                        ...[1.0, 2.0, 3.0].map((w) {
                          final isSelected = _weight == w;
                          return Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: GestureDetector(
                              onTap: () {
                                HapticFeedback.selectionClick();
                                setState(() {
                                  _weight = w;
                                  _weightController.text = w.toInt().toString();
                                });
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                width: 50,
                                height: 50,
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colorScheme.primary.withValues(alpha: 0.15)
                                      : isDark
                                          ? colorScheme.onSurface.withValues(alpha: 0.05)
                                          : colorScheme.onSurface.withValues(alpha: 0.03),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: isSelected
                                        ? colorScheme.primary
                                        : colorScheme.outline.withValues(alpha: 0.1),
                                    width: isSelected ? 2 : 1,
                                  ),
                                ),
                                child: Center(
                                  child: Text(
                                    w.toInt().toString(),
                                    style: GoogleFonts.inter(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurface.withValues(alpha: 0.6),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark
                                  ? colorScheme.onSurface.withValues(alpha: 0.05)
                                  : colorScheme.onSurface.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: colorScheme.outline.withValues(alpha: 0.1),
                              ),
                            ),
                            child: TextField(
                              controller: _weightController,
                              keyboardType:
                                  const TextInputType.numberWithOptions(decimal: true),
                              textInputAction: TextInputAction.done,
                              onEditingComplete: () =>
                                  FocusScope.of(context).unfocus(),
                              inputFormatters: [
                                FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                              ],
                              style: GoogleFonts.inter(
                                fontSize: 16,
                                color: colorScheme.onSurface,
                              ),
                              cursorColor: colorScheme.primary,
                              decoration: InputDecoration(
                                hintText: l10n.other,
                                hintStyle: GoogleFonts.inter(
                                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                                ),
                                border: InputBorder.none,
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                              ),
                              onChanged: (value) {
                                final parsed = double.tryParse(value);
                                if (parsed != null && parsed > 0) {
                                  setState(() => _weight = parsed);
                                }
                              },
                            ),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 28),

                    Row(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTap: () => Navigator.pop(context),
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: isDark
                                    ? colorScheme.onSurface.withValues(alpha: 0.05)
                                    : colorScheme.onSurface.withValues(alpha: 0.03),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: colorScheme.outline.withValues(alpha: 0.1),
                                ),
                              ),
                              child: Center(
                                child: Text(
                                  l10n.cancel,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              HapticFeedback.lightImpact();
                              if (widget.onSave != null) {
                                widget.onSave!(_selectedMark, _weight);
                              } else if (isEditing) {
                                widget.vm.editVirtualMark(
                                  widget.subjectId,
                                  widget.existingMark!.id,
                                  _selectedMark,
                                  _weight,
                                );
                              } else {
                                widget.vm.addVirtualMark(
                                  widget.subjectId,
                                  _selectedMark,
                                  _weight,
                                );
                              }
                              Navigator.pop(context);
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Center(
                                child: Text(
                                  isEditing ? l10n.save : l10n.add,
                                  style: GoogleFonts.inter(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
    );
  }
}

class _SubjectDetailSheet extends StatelessWidget {
  final SubjectData subject;
  final AppLocalizations l10n;

  const _SubjectDetailSheet({required this.subject, required this.l10n});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final vm = context.watch<MarksViewModel>();
    final grading = context.watch<GradingProvider>();
    final hasChanges = vm.hasChanges(subject.id);
    final modifiedAvg = vm.calculateModifiedAverage(subject.id);
    final baseAverage = hasChanges && modifiedAvg != "-"
        ? modifiedAvg
        : (subject.average != "-" ? subject.average : subject.calculatedAverage);
    final baseAverageValue = double.tryParse(baseAverage);
    final predictedGrade = grading.showPredictedGrade &&
            baseAverage != "-" &&
            (baseAverageValue ?? 0) > 0
        ? grading.getPredictedGrade(baseAverage)
        : null;

    Color predictedColor() {
      if (predictedGrade == null) return grading.getAverageColorFromString(baseAverage);
      if (predictedGrade.contains('-')) {
        final parts = predictedGrade.split('-');
        final g1 = int.tryParse(parts.first);
        final g2 = int.tryParse(parts.last);
        if (g1 != null && g2 != null) {
          final c1 = grading.getColorForGrade(g1);
          final c2 = grading.getColorForGrade(g2);
          return Color.lerp(c1, c2, 0.5) ?? c1;
        }
      }
      final single = int.tryParse(predictedGrade.replaceAll(RegExp(r'\D'), ''));
      if (single != null) return grading.getColorForGrade(single);
      return grading.getAverageColorFromString(baseAverage);
    }

    return DraggableScrollableSheet(
      initialChildSize: 0.5,
      minChildSize: 0.3,
      maxChildSize: 0.9,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(24),
                  children: [
                    Text(
                      subject.name,
                      style: GoogleFonts.outfit(
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 24),

                    _DetailCard(
                      icon: Icons.person_outline_rounded,
                      label: l10n.teacher,
                      value: subject.teacher ?? l10n.noData,
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _DetailCard(
                      icon: Icons.bar_chart_rounded,
                      label: l10n.rating,
                      value: subject.rating ?? l10n.noData,
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),

                    if (subject.totalMark != null) ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        icon: Icons.verified_outlined,
                        label: l10n.finalMark,
                        value: subject.totalMark!,
                        colorScheme: colorScheme,
                        isDark: isDark,
                        valueColor: grading.getAverageColorFromString(subject.totalMark!),
                      ),
                    ],

                    if (predictedGrade != null) ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        icon: Icons.flag_rounded,
                        label: l10n.prediction,
                        value: predictedGrade,
                        colorScheme: colorScheme,
                        isDark: isDark,
                        valueColor: predictedColor(),
                      ),
                    ],

                    if (hasChanges && modifiedAvg != "-") ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        icon: Icons.edit_note_rounded,
                        label: l10n.modifiedAverage,
                        value: modifiedAvg,
                        colorScheme: colorScheme,
                        isDark: isDark,
                        valueColor: grading.getAverageColorFromString(modifiedAvg),
                      ),
                    ],

                    if (subject.calculatedAverage != "-" &&
                        subject.calculatedAverage != subject.average) ...[
                      const SizedBox(height: 12),
                      _DetailCard(
                        icon: Icons.calculate_outlined,
                        label: l10n.calculatedAverage,
                        value: subject.calculatedAverage,
                        colorScheme: colorScheme,
                        isDark: isDark,
                        valueColor: grading.getAverageColorFromString(subject.calculatedAverage),
                      ),
                    ],

                    const SizedBox(height: 12),
                    _DetailCard(
                      icon: Icons.percent_rounded,
                      label: l10n.averageScoreApi,
                      value: subject.average,
                      colorScheme: colorScheme,
                      isDark: isDark,
                      valueColor: grading.getAverageColorFromString(subject.average),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DetailCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final ColorScheme colorScheme;
  final bool isDark;
  final Color? valueColor;

  const _DetailCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.colorScheme,
    required this.isDark,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: (valueColor ?? colorScheme.primary).withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              size: 20,
              color: valueColor ?? colorScheme.primary,
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
                  value,
                  style: GoogleFonts.inter(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: valueColor ?? colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}