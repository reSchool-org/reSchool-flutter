import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' as intl;
import 'package:provider/provider.dart';
import '../l10n/app_localizations.dart';
import '../models/plan_success_models.dart';
import '../viewmodels/marks_viewmodel.dart';
import '../utils/app_font.dart';

class MarksAnalyticsView extends StatefulWidget {
  final String? initialUnitId;
  final String? controlledUnitId;
  final bool showSubjectSelector;

  const MarksAnalyticsView({
    super.key,
    this.initialUnitId,
    this.controlledUnitId,
    this.showSubjectSelector = true,
  });

  @override
  State<MarksAnalyticsView> createState() => _MarksAnalyticsViewState();
}

class _MarksAnalyticsViewState extends State<MarksAnalyticsView> {
  int? _selectedUnitId;

  @override
  void initState() {
    super.initState();
    if (widget.showSubjectSelector) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final vm = context.read<MarksViewModel>();
        vm.loadAnalyticsUnits();
      });
    }
    _selectedUnitId = int.tryParse(widget.initialUnitId ?? '');
  }

  @override
  void didUpdateWidget(covariant MarksAnalyticsView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.controlledUnitId != null) return;

    if (oldWidget.initialUnitId != widget.initialUnitId && widget.initialUnitId != null) {
      final next = int.tryParse(widget.initialUnitId!);
      if (next != null && next != _selectedUnitId) {
        setState(() => _selectedUnitId = next);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<MarksViewModel>();
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    int? unitId;
    if (widget.controlledUnitId != null) {
      unitId = int.tryParse(widget.controlledUnitId!);
    } else {
      final options = <({int id, String name})>[];
      if (vm.analyticsUnits.isNotEmpty) {
        for (final u in vm.analyticsUnits) {
          options.add((id: u.unitId, name: u.name));
        }
      } else if (vm.subjects.isNotEmpty) {
        // запасной путь, если /getPupilUnits почему то недоступен
        for (final s in vm.subjects) {
          final id = int.tryParse(s.id);
          if (id == null) continue;
          options.add((id: id, name: s.name));
        }
      }

      options.sort((a, b) => a.name.compareTo(b.name));

      if (_selectedUnitId == null && options.isNotEmpty) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          setState(() => _selectedUnitId = options.first.id);
        });
      }

      unitId = _selectedUnitId;
    }

    if (unitId != null &&
        vm.getPlanSuccessForUnit(unitId) == null &&
        !vm.isPlanSuccessLoading(unitId) &&
        vm.getPlanSuccessError(unitId) == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<MarksViewModel>().loadPlanSuccessForUnit(unitId!);
      });
    }

    return RefreshIndicator(
      onRefresh: () async {
        if (unitId != null) {
          await context.read<MarksViewModel>().loadPlanSuccessForUnit(unitId, forceRefresh: true);
        }
      },
      color: colorScheme.primary,
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.showSubjectSelector && widget.controlledUnitId == null)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
                child: _SubjectSelector(
                  title: l10n.analyticsViewTitle,
                  options: (() {
                    final opts = <({int id, String name})>[];
                    if (vm.analyticsUnits.isNotEmpty) {
                      for (final u in vm.analyticsUnits) {
                        opts.add((id: u.unitId, name: u.name));
                      }
                    } else if (vm.subjects.isNotEmpty) {
                      for (final s in vm.subjects) {
                        final id = int.tryParse(s.id);
                        if (id == null) continue;
                        opts.add((id: id, name: s.name));
                      }
                    }
                    opts.sort((a, b) => a.name.compareTo(b.name));
                    return opts;
                  })(),
                  selectedId: unitId,
                  isLoadingUnits: vm.analyticsUnitsLoading,
                  isRefreshing: (unitId != null && vm.isPlanSuccessLoading(unitId)) || vm.analyticsUnitsLoading,
                  unitsError: vm.analyticsUnitsError,
                  colorScheme: colorScheme,
                  isDark: isDark,
                  onSelect: (id) {
                    setState(() => _selectedUnitId = id);
                    context.read<MarksViewModel>().loadPlanSuccessForUnit(id);
                  },
                  onRefresh: () async {
                    if (unitId != null) {
                      await context.read<MarksViewModel>().loadPlanSuccessForUnit(unitId, forceRefresh: true);
                    } else {
                      await context.read<MarksViewModel>().loadAnalyticsUnits(forceRefresh: true);
                    }
                  },
                ),
              ),
            )
          else
            const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _buildSummary(vm, unitId, colorScheme, isDark, l10n),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
              child: _buildChartCard(vm, unitId, colorScheme, isDark, l10n),
            ),
          ),
          ..._buildTopicsSlivers(vm, unitId, colorScheme, isDark, l10n),
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ),
    );
  }

  Widget _buildSummary(
    MarksViewModel vm,
    int? unitId,
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    if (unitId == null) {
      return const SizedBox.shrink();
    }

    final root = vm.getPlanSuccessForUnit(unitId);
    if (root == null) {
      if (vm.isPlanSuccessLoading(unitId)) return const SizedBox.shrink();
      return const SizedBox.shrink();
    }

    final classYear = root.user?.groupAvgYear;
    final studentYear = root.user?.overMarkYear;

    return Row(
      children: [
        Expanded(
          child: _MetricCard(
            title: l10n.analyticsClassAvgYear,
            value: _formatAvg(classYear),
            colorScheme: colorScheme,
            isDark: isDark,
            accent: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _MetricCard(
            title: l10n.analyticsStudentAvgYear,
            value: _formatAvg(studentYear),
            colorScheme: colorScheme,
            isDark: isDark,
            accent: colorScheme.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildChartCard(
    MarksViewModel vm,
    int? unitId,
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    if (unitId == null) {
      return _EmptyCard(
        title: l10n.analyticsNoSubjectTitle,
        subtitle: l10n.analyticsNoSubjectSubtitle,
        colorScheme: colorScheme,
        isDark: isDark,
      );
    }

    final error = vm.getPlanSuccessError(unitId);
    if (error != null) {
      return _ErrorCard(
        title: l10n.loadingError,
        message: error,
        colorScheme: colorScheme,
        isDark: isDark,
        onRetry: () => context.read<MarksViewModel>().loadPlanSuccessForUnit(unitId, forceRefresh: true),
      );
    }

    final loading = vm.isPlanSuccessLoading(unitId);
    final root = vm.getPlanSuccessForUnit(unitId);
    if (root == null) {
      return Container(
        height: 220,
        decoration: BoxDecoration(
          color: isDark ? colorScheme.onSurface.withValues(alpha: 0.04) : colorScheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
        ),
        child: Center(
          child: loading
              ? CircularProgressIndicator(color: colorScheme.primary)
              : Text(
                  l10n.analyticsNoData,
                  style: appFont(context,
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
        ),
      );
    }

    final points = _mergePoints(root);
    final classColor = colorScheme.primary;
    final studentColor = _pickDistinctStudentColor(colorScheme);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.onSurface.withValues(alpha: 0.04) : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  l10n.analyticsChartTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(context,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
              ),
              Wrap(
                alignment: WrapAlignment.end,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 10,
                runSpacing: 6,
                children: [
                  _LegendDot(label: l10n.analyticsClassLabel, color: classColor, colorScheme: colorScheme),
                  _LegendDot(label: l10n.analyticsStudentLabel, color: studentColor, colorScheme: colorScheme),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 206,
            child: _InteractivePlanComparisonChart(
              points: points,
              xLabels: points.map((p) => _buildXAxisLabel(p, l10n)).toList(),
              classColor: classColor,
              studentColor: studentColor,
              textColor: colorScheme.onSurface.withValues(alpha: 0.55),
              gridColor: colorScheme.outline.withValues(alpha: 0.12),
              surfaceColor: colorScheme.surface,
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildTopicsSlivers(
    MarksViewModel vm,
    int? unitId,
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    if (unitId == null) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _EmptyCard(
              title: l10n.analyticsNoSubjectTitle,
              subtitle: l10n.analyticsNoSubjectSubtitle,
              colorScheme: colorScheme,
              isDark: isDark,
            ),
          ),
        ),
      ];
    }

    final root = vm.getPlanSuccessForUnit(unitId);
    if (root == null) {
      return const [SliverToBoxAdapter(child: SizedBox.shrink())];
    }

    final points = _mergePoints(root);
    if (points.isEmpty) {
      return [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: _EmptyCard(
              title: l10n.analyticsNoData,
              subtitle: l10n.analyticsNoDataHint,
              colorScheme: colorScheme,
              isDark: isDark,
            ),
          ),
        ),
      ];
    }

    return [
      SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.analyticsByTopicTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(context,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                ),
                Wrap(
                  alignment: WrapAlignment.end,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 18,
                  runSpacing: 6,
                  children: [
                    Text(
                      l10n.analyticsClassLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(context,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    Text(
                      l10n.analyticsStudentLabel,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: appFont(context,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ),
      SliverList.separated(
        itemCount: points.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (context, index) {
          final p = points[index];
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: _TopicRow(
              point: p,
              colorScheme: colorScheme,
              isDark: isDark,
              l10n: l10n,
            ),
          );
        },
      ),
    ];
  }

  List<_PlanPoint> _mergePoints(PlanSuccessRoot root) {
    final avgByRn = <int, PlanSuccessAvgItem>{};
    for (final a in root.userAvg) {
      if (a.rn == 0) continue;
      avgByRn[a.rn] = a;
    }

    final points = <_PlanPoint>[];
    for (final t in root.topics) {
      final a = avgByRn[t.rn];
      points.add(_PlanPoint(
        rn: t.rn,
        topicName: t.topicName,
        sectionName: t.sectionName,
        minDate: t.minLessonDate,
        maxDate: t.maxLessonDate,
        lessons: t.lessonCount,
        classAvg: a?.groupAvg,
        studentAvg: a?.overMark,
      ));
    }

    points.sort((a, b) => a.rn.compareTo(b.rn));
    return points;
  }

  String _formatAvg(double? v) {
    if (v == null) return '-';
    if (v == 0) return '-';
    if (v % 1 == 0) return v.toStringAsFixed(0);
    return v.toStringAsFixed(2);
  }
}

class _PlanPoint {
  final int rn;
  final String topicName;
  final String sectionName;
  final DateTime? minDate;
  final DateTime? maxDate;
  final int lessons;
  final double? classAvg;
  final double? studentAvg;

  _PlanPoint({
    required this.rn,
    required this.topicName,
    required this.sectionName,
    required this.minDate,
    required this.maxDate,
    required this.lessons,
    required this.classAvg,
    required this.studentAvg,
  });
}

Color _pickDistinctStudentColor(ColorScheme cs) {
  final primary = cs.primary;
  final secondary = cs.secondary;
  final diff = (primary.r - secondary.r).abs() +
      (primary.g - secondary.g).abs() +
      (primary.b - secondary.b).abs();
  if (diff < 160) return const Color(0xFFF97316); // оранжевый
  return secondary;
}

class _SubjectSelector extends StatelessWidget {
  final String title;
  final List<({int id, String name})> options;
  final int? selectedId;
  final bool isLoadingUnits;
  final bool isRefreshing;
  final String? unitsError;
  final ColorScheme colorScheme;
  final bool isDark;
  final ValueChanged<int> onSelect;
  final Future<void> Function() onRefresh;

  const _SubjectSelector({
    required this.title,
    required this.options,
    required this.selectedId,
    required this.isLoadingUnits,
    required this.isRefreshing,
    required this.unitsError,
    required this.colorScheme,
    required this.isDark,
    required this.onSelect,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              title,
              style: appFont(context,
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const Spacer(),
            Tooltip(
              message: l10n.updateMarks,
              child: Container(
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colorScheme.primary.withValues(alpha: 0.18)),
                ),
                child: IconButton(
                  icon: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 150),
                    child: isRefreshing
                        ? SizedBox(
                            key: const ValueKey('spinner'),
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary,
                            ),
                          )
                        : Icon(
                            Icons.refresh_rounded,
                            key: const ValueKey('icon'),
                            color: colorScheme.primary,
                            size: 18,
                          ),
                  ),
                  onPressed: isRefreshing
                      ? null
                      : () {
                          onRefresh();
                        },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        if (unitsError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              unitsError!,
              style: appFont(context,
                fontSize: 12,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: isDark ? colorScheme.onSurface.withValues(alpha: 0.05) : colorScheme.onSurface.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colorScheme.outline.withValues(alpha: 0.10)),
          ),
          child: Row(
            children: [
              Icon(
                Icons.bookmark_outline_rounded,
                size: 18,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: DropdownButton<int>(
                  value: selectedId,
                  isExpanded: true,
                  underline: const SizedBox.shrink(),
                  hint: Text(
                    l10n.analyticsSelectSubject,
                    style: appFont(context,
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                  ),
                  items: options
                      .map(
                        (o) => DropdownMenuItem<int>(
                          value: o.id,
                          child: Text(
                            o.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: appFont(context,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (v) {
                    if (v == null) return;
                    onSelect(v);
                  },
                ),
              ),
              if (isLoadingUnits)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final ColorScheme colorScheme;
  final bool isDark;
  final Color accent;

  const _MetricCard({
    required this.title,
    required this.value,
    required this.colorScheme,
    required this.isDark,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.onSurface.withValues(alpha: 0.04) : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: appFont(context,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                value,
                style: appFont(context,
                  fontSize: 22,
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

class _LegendDot extends StatelessWidget {
  final String label;
  final Color color;
  final ColorScheme colorScheme;

  const _LegendDot({required this.label, required this.color, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 120),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              softWrap: false,
              style: appFont(context,
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TopicRow extends StatelessWidget {
  final _PlanPoint point;
  final ColorScheme colorScheme;
  final bool isDark;
  final AppLocalizations l10n;

  const _TopicRow({
    required this.point,
    required this.colorScheme,
    required this.isDark,
    required this.l10n,
  });

  @override
  Widget build(BuildContext context) {
    final dateLabel = _formatRange(point.minDate, point.maxDate, l10n);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.onSurface.withValues(alpha: 0.04) : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  point.topicName.isEmpty ? l10n.noData : point.topicName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: appFont(context,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 10,
                  runSpacing: 4,
                  children: [
                    if (dateLabel.isNotEmpty)
                      Text(
                        dateLabel,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: appFont(context,
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.50),
                        ),
                      ),
                    if (point.lessons > 0)
                      Text(
                        l10n.analyticsLessonsCount(point.lessons),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        softWrap: false,
                        style: appFont(context,
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.50),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _AvgPill(value: point.classAvg, color: colorScheme.primary, colorScheme: colorScheme),
          const SizedBox(width: 10),
          _AvgPill(value: point.studentAvg, color: colorScheme.secondary, colorScheme: colorScheme),
        ],
      ),
    );
  }
}

class _AvgPill extends StatelessWidget {
  final double? value;
  final Color color;
  final ColorScheme colorScheme;

  const _AvgPill({required this.value, required this.color, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    final v = value;
    final text = (v == null || v == 0) ? '-' : (v % 1 == 0 ? v.toStringAsFixed(0) : v.toStringAsFixed(2));
    final isEmpty = text == '-';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: isEmpty ? colorScheme.onSurface.withValues(alpha: 0.05) : color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: isEmpty ? colorScheme.outline.withValues(alpha: 0.08) : color.withValues(alpha: 0.22),
        ),
      ),
      child: Text(
        text,
        style: appFont(context,
          fontSize: 14,
          fontWeight: FontWeight.w700,
          color: isEmpty ? colorScheme.onSurface.withValues(alpha: 0.55) : color,
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  final String title;
  final String subtitle;
  final ColorScheme colorScheme;
  final bool isDark;

  const _EmptyCard({
    required this.title,
    required this.subtitle,
    required this.colorScheme,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.onSurface.withValues(alpha: 0.04) : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.insights_rounded, color: colorScheme.primary, size: 20),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: appFont(context,
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: appFont(context,
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
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

class _ErrorCard extends StatelessWidget {
  final String title;
  final String message;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onRetry;

  const _ErrorCard({
    required this.title,
    required this.message,
    required this.colorScheme,
    required this.isDark,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
      decoration: BoxDecoration(
        color: isDark ? colorScheme.error.withValues(alpha: 0.07) : colorScheme.error.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.error.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: appFont(context,
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            style: appFont(context,
              fontSize: 12,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton(
              onPressed: onRetry,
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: Text(l10n.retry, style: appFont(context, fontWeight: FontWeight.w600)),
            ),
          ),
        ],
      ),
    );
  }
}

class _InteractivePlanComparisonChart extends StatefulWidget {
  final List<_PlanPoint> points;
  final List<String> xLabels;
  final Color classColor;
  final Color studentColor;
  final Color textColor;
  final Color gridColor;
  final Color surfaceColor;

  const _InteractivePlanComparisonChart({
    required this.points,
    required this.xLabels,
    required this.classColor,
    required this.studentColor,
    required this.textColor,
    required this.gridColor,
    required this.surfaceColor,
  });

  @override
  State<_InteractivePlanComparisonChart> createState() => _InteractivePlanComparisonChartState();
}

class _InteractivePlanComparisonChartState extends State<_InteractivePlanComparisonChart> {
  _TooltipData? _tooltip;
  final ScrollController _hScroll = ScrollController();

  static const double _xStep = 56.0;

  @override
  void initState() {
    super.initState();
    _hScroll.addListener(_clearTooltip);
  }

  @override
  void dispose() {
    _hScroll.removeListener(_clearTooltip);
    _hScroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
        final scale = _ChartScale.fromPoints(widget.points);

        final targets = <_HitTarget>[];
        final n = widget.points.length;

        final contentWidth = math.max(
          viewportSize.width,
          _PlanComparisonPainter.minWidthForPoints(n, _xStep),
        );

        final contentSize = Size(contentWidth, viewportSize.height);
        final rect = _PlanComparisonPainter.plotRectForSize(contentSize);

        for (int i = 0; i < n; i++) {
          final p = widget.points[i];
          final x = _PlanComparisonPainter.xForIndex(i, n, rect, _xStep);

          final classV = p.classAvg;
          if (classV != null && classV != 0) {
            targets.add(_HitTarget(
              series: _SeriesType.classAvg,
              center: Offset(x, scale.valueToY(classV, rect)),
              value: classV,
              color: widget.classColor,
            ));
          }

          final studentV = p.studentAvg;
          if (studentV != null && studentV != 0) {
            targets.add(_HitTarget(
              series: _SeriesType.studentAvg,
              center: Offset(x, scale.valueToY(studentV, rect)),
              value: studentV,
              color: widget.studentColor,
            ));
          }
        }

        return Scrollbar(
          controller: _hScroll,
          child: SingleChildScrollView(
            controller: _hScroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: contentWidth,
              height: viewportSize.height,
              child: Stack(
                children: [
                  CustomPaint(
                    painter: _PlanComparisonPainter(
                      textStyle: appFont(context, textStyle: Theme.of(context).textTheme.bodyMedium!),
                      points: widget.points,
                      classColor: widget.classColor,
                      studentColor: widget.studentColor,
                      textColor: widget.textColor,
                      gridColor: widget.gridColor,
                surfaceColor: widget.surfaceColor,
                xStep: _xStep,
                xLabels: widget.xLabels,
              ),
              child: const SizedBox.expand(),
            ),
                  ...targets.map((t) {
                    const hitSize = 22.0;
                    return Positioned(
                      left: t.center.dx - hitSize / 2,
                      top: t.center.dy - hitSize / 2,
                      width: hitSize,
                      height: hitSize,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        onEnter: (_) => _showTooltipFor(t),
                        onExit: (_) => _clearTooltip(),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticFeedback.selectionClick();
                            _showTooltipFor(t);
                          },
                          child: const SizedBox.expand(),
                        ),
                      ),
                    );
                  }),
                  if (_tooltip != null)
                    Positioned(
                      left: _tooltip!.topLeft.dx,
                      top: _tooltip!.topLeft.dy,
                      child: _TooltipBubble(
                        label: _tooltip!.label,
                        value: _tooltip!.valueLabel,
                        color: _tooltip!.color,
                        surface: widget.surfaceColor,
                        border: widget.gridColor.withValues(alpha: 0.9),
                        text: widget.textColor,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showTooltipFor(_HitTarget t) {
    final l10n = AppLocalizations.of(context)!;
    final label = t.series == _SeriesType.classAvg ? l10n.analyticsClassLabel : l10n.analyticsStudentLabel;
    final valueLabel = _formatValue(t.value);

    const bubbleSize = Size(140, 64);
    const margin = 10.0;

    final renderBox = context.findRenderObject() as RenderBox?;
    final localSize = renderBox?.size ?? Size.zero;
    final scrollOffset = _hScroll.hasClients ? _hScroll.offset : 0.0;

    final above = Offset(
      t.center.dx - bubbleSize.width / 2,
      t.center.dy - bubbleSize.height - 12,
    );
    final below = Offset(
      t.center.dx - bubbleSize.width / 2,
      t.center.dy + 12,
    );

    Offset topLeft = above;
    if (topLeft.dy < margin) topLeft = below;

    final visibleLeft = scrollOffset + margin;
    final visibleRight = scrollOffset + localSize.width - bubbleSize.width - margin;

    topLeft = Offset(
      topLeft.dx.clamp(visibleLeft, math.max(visibleLeft, visibleRight)),
      topLeft.dy.clamp(margin, math.max(margin, localSize.height - bubbleSize.height - margin)),
    );

    setState(() {
      _tooltip = _TooltipData(
        topLeft: topLeft,
        label: label,
        valueLabel: valueLabel,
        color: t.color,
      );
    });
  }

  void _clearTooltip() {
    if (_tooltip == null) return;
    setState(() => _tooltip = null);
  }
}

enum _SeriesType { classAvg, studentAvg }

class _HitTarget {
  final _SeriesType series;
  final Offset center;
  final double value;
  final Color color;

  _HitTarget({
    required this.series,
    required this.center,
    required this.value,
    required this.color,
  });
}

class _TooltipData {
  final Offset topLeft;
  final String label;
  final String valueLabel;
  final Color color;

  _TooltipData({
    required this.topLeft,
    required this.label,
    required this.valueLabel,
    required this.color,
  });
}

class _TooltipBubble extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final Color surface;
  final Color border;
  final Color text;

  const _TooltipBubble({
    required this.label,
    required this.value,
    required this.color,
    required this.surface,
    required this.border,
    required this.text,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 140,
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: surface.withValues(alpha: 0.96),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: border),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 14,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 10,
              height: 10,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: appFont(context,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: text.withValues(alpha: 0.75),
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    value,
                    style: appFont(context,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                      color: text,
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

class _ChartScale {
  final double minV;
  final double maxV;
  final List<int> ticks;

  _ChartScale({required this.minV, required this.maxV, required this.ticks});

  factory _ChartScale.fromPoints(List<_PlanPoint> points) {
    final values = <double>[];
    for (final p in points) {
      if (p.classAvg != null && p.classAvg != 0) values.add(p.classAvg!);
      if (p.studentAvg != null && p.studentAvg != 0) values.add(p.studentAvg!);
    }

    double minV = 2.0;
    double maxV = 5.0;
    if (values.isNotEmpty) {
      minV = math.min(minV, values.reduce(math.min));
      maxV = math.max(maxV, values.reduce(math.max));
    }

    if ((maxV - minV).abs() < 0.001) {
      minV -= 1;
      maxV += 1;
    }

    final minTick = math.min(2, minV.floor());
    final maxTick = math.max(5, maxV.ceil());
    final ticks = <int>[];
    for (int t = minTick; t <= maxTick; t++) {
      ticks.add(t);
    }

    return _ChartScale(minV: minV, maxV: maxV, ticks: ticks);
  }

  double valueToY(double v, Rect rect) {
    final t = (v - minV) / (maxV - minV);
    return rect.bottom - rect.height * t;
  }
}

class _PlanComparisonPainter extends CustomPainter {
  final TextStyle textStyle;
  final List<_PlanPoint> points;
  final Color classColor;
  final Color studentColor;
  final Color textColor;
  final Color gridColor;
  final Color surfaceColor;
  final double xStep;
  final List<String> xLabels;

  _PlanComparisonPainter({
    required this.textStyle,
    required this.points,
    required this.classColor,
    required this.studentColor,
    required this.textColor,
    required this.gridColor,
    required this.surfaceColor,
    required this.xStep,
    required this.xLabels,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = plotRectForSize(size);
    final scale = _ChartScale.fromPoints(points);

    if (rect.width <= 0 || rect.height <= 0) {
      final tp = TextPainter(
        text: TextSpan(
          text: '-',
          style: textStyle.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
      return;
    }

    final hasAnyValues = points.any((p) =>
        (p.classAvg != null && p.classAvg != 0) || (p.studentAvg != null && p.studentAvg != 0));
    if (!hasAnyValues) {
      final tp = TextPainter(
        text: TextSpan(
          text: '-',
          style: textStyle.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
            color: textColor,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2));
      return;
    }

    _drawYAxisAndDashedGrid(canvas, size, rect, scale);

    final classPath = _buildPath(rect, scale, (p) => p.classAvg);
    final studentPath = _buildPath(rect, scale, (p) => p.studentAvg);

    final classPaint = Paint()
      ..color = classColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final studentPaint = Paint()
      ..color = studentColor
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    if (studentPath != null) canvas.drawPath(studentPath, studentPaint);
    if (classPath != null) canvas.drawPath(classPath, classPaint);

    _drawDots(canvas, rect, scale, (p) => p.classAvg, classColor);
    _drawDots(canvas, rect, scale, (p) => p.studentAvg, studentColor);

    _drawXAxisLabels(canvas, size, rect);
  }

  Path? _buildPath(
    Rect rect,
    _ChartScale scale,
    double? Function(_PlanPoint p) selector,
  ) {
    if (points.length < 2) return null;
    final n = points.length;
    final path = Path();
    bool started = false;

    for (int i = 0; i < n; i++) {
      final v = selector(points[i]);
      if (v == null || v == 0) {
        started = false;
        continue;
      }

      final x = xForIndex(i, n, rect, xStep);
      final y = scale.valueToY(v, rect);

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    if (!started) return null;
    return path;
  }

  void _drawDots(
    Canvas canvas,
    Rect rect,
    _ChartScale scale,
    double? Function(_PlanPoint p) selector,
    Color color,
  ) {
    final n = points.length;
    final fill = Paint()..color = color;
    final stroke = Paint()
      ..color = Colors.white.withValues(alpha: 0.9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;

    for (int i = 0; i < n; i++) {
      final v = selector(points[i]);
      if (v == null || v == 0) continue;

      final x = xForIndex(i, n, rect, xStep);
      final y = scale.valueToY(v, rect);
      canvas.drawCircle(Offset(x, y), 4.0, fill);
      canvas.drawCircle(Offset(x, y), 4.0, stroke);
    }
  }

  void _drawYAxisAndDashedGrid(Canvas canvas, Size size, Rect rect, _ChartScale scale) {
    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;

    for (final t in scale.ticks) {
      final y = scale.valueToY(t.toDouble(), rect);
      if (y < rect.top - 1 || y > rect.bottom + 1) continue;

      // пунктир от подписи через весь график
      _drawDashedLine(canvas, Offset(rect.left, y), Offset(rect.right, y), gridPaint);

      // подписи по бокам
      final tp = TextPainter(
        text: TextSpan(
          text: t.toString(),
          style: textStyle.copyWith(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: textColor.withValues(alpha: 0.55),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();

      tp.paint(canvas, Offset(10, y - tp.height / 2));
      tp.paint(canvas, Offset(size.width - 10 - tp.width, y - tp.height / 2));
    }
  }

  void _drawDashedLine(Canvas canvas, Offset a, Offset b, Paint paint) {
    const dash = 6.0;
    const gap = 5.0;
    final dx = b.dx - a.dx;
    final dy = b.dy - a.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    if (len <= 0.001) return;
    final dir = Offset(dx / len, dy / len);

    double dist = 0;
    while (dist < len) {
      final start = a + dir * dist;
      final end = a + dir * math.min(dist + dash, len);
      canvas.drawLine(start, end, paint);
      dist += dash + gap;
    }
  }

  void _drawXAxisLabels(Canvas canvas, Size size, Rect rect) {
    if (xLabels.isEmpty) return;
    final n = points.length;
    if (n == 0) return;

    final style = textStyle.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w600,
      height: 1.05,
      color: textColor.withValues(alpha: 0.55),
    );

    final maxWidth = math.max(12.0, xStep - 6.0);
    final y = rect.bottom + 6;

    for (int i = 0; i < n; i++) {
      final label = i < xLabels.length ? xLabels[i] : '';
      if (label.isEmpty) continue;

      final x = xForIndex(i, n, rect, xStep);
      final tp = TextPainter(
        text: TextSpan(text: label, style: style),
        textAlign: TextAlign.center,
        textDirection: TextDirection.ltr,
        maxLines: 2,
        ellipsis: '…',
      )..layout(maxWidth: maxWidth);

      final dx = (x - tp.width / 2)
          .clamp(0.0, math.max(0.0, size.width - tp.width))
          .toDouble();
      tp.paint(canvas, Offset(dx, y));
    }
  }

  static Rect plotRectForSize(Size size) {
    const left = 34.0;
    const right = 34.0;
    const top = 10.0;
    const bottom = 36.0; // место под подписи оси x
    return Rect.fromLTWH(
      left,
      top,
      math.max(0, size.width - left - right),
      math.max(0, size.height - top - bottom),
    );
  }

  static double minWidthForPoints(int n, double xStep) {
    const left = 34.0;
    const right = 34.0;
    if (n <= 1) return left + right + 1;
    return left + right + (xStep * (n - 1));
  }

  static double xForIndex(int i, int n, Rect rect, double xStep) {
    if (n <= 1) return rect.center.dx;
    return rect.left + (xStep * i);
  }

  @override
  bool shouldRepaint(covariant _PlanComparisonPainter oldDelegate) {
    return oldDelegate.textStyle != textStyle ||
        oldDelegate.points != points ||
        oldDelegate.classColor != classColor ||
        oldDelegate.studentColor != studentColor ||
        oldDelegate.textColor != textColor ||
        oldDelegate.gridColor != gridColor ||
        oldDelegate.surfaceColor != surfaceColor ||
        oldDelegate.xStep != xStep ||
        oldDelegate.xLabels != xLabels;
  }
}

String _formatRange(DateTime? minDate, DateTime? maxDate, AppLocalizations l10n) {
  if (minDate == null && maxDate == null) return '';

  final locale = l10n.locale.languageCode;
  final fmt = intl.DateFormat('dd.MM.yyyy', locale);

  if (minDate != null && maxDate != null) {
    final a = fmt.format(minDate);
    final b = fmt.format(maxDate);
    return a == b ? a : '$a - $b';
  }
  if (minDate != null) return fmt.format(minDate);
  return fmt.format(maxDate!);
}

String _formatValue(double v) {
  if (v % 1 == 0) return v.toStringAsFixed(0);
  return v.toStringAsFixed(2);
}

String _buildXAxisLabel(_PlanPoint p, AppLocalizations l10n) {
  final locale = l10n.locale.languageCode;
  final dateLabel = _shortDateRangeLabel(p.minDate, p.maxDate, locale);

  final topic = p.topicName.trim();
  final looksLikeDate = _looksLikeDateRange(topic);

  if (looksLikeDate) {
    return dateLabel.isEmpty ? topic : dateLabel;
  }

  if (dateLabel.isEmpty) return topic;
  if (topic.isEmpty) return dateLabel;
  return '$dateLabel\n$topic';
}

String _shortDateRangeLabel(DateTime? minDate, DateTime? maxDate, String localeCode) {
  if (minDate == null && maxDate == null) return '';
  final fmt = intl.DateFormat('dd.MM', localeCode);

  if (minDate != null && maxDate != null) {
    final a = fmt.format(minDate);
    final b = fmt.format(maxDate);
    return a == b ? a : '$a-$b';
  }
  if (minDate != null) return fmt.format(minDate);
  return fmt.format(maxDate!);
}

bool _looksLikeDateRange(String s) {
  // период приходит двумя датами через дефис
  final t = s.trim();
  if (t.isEmpty) return false;
  final re = RegExp(r'^\d{1,2}\.\d{1,2}\.\d{2,4}\s*-\s*\d{1,2}\.\d{1,2}\.\d{2,4}$');
  return re.hasMatch(t);
}
