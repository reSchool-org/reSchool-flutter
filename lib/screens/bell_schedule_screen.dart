import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/bell_schedule_provider.dart';
import '../widgets/app_card.dart';
import 'preset_edit_screen.dart';
import '../utils/app_font.dart';

class BellScheduleScreen extends StatefulWidget {
  const BellScheduleScreen({super.key});

  @override
  State<BellScheduleScreen> createState() => _BellScheduleScreenState();
}

class _BellScheduleScreenState extends State<BellScheduleScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

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

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return GestureDetector(
      onTap: _dismissKeyboard,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Звонки',
            style: appFont(context,
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: colorScheme.onSurface,
            ),
          ),
        ),
        body: Consumer<BellScheduleProvider>(
          builder: (context, provider, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: SafeArea(child: _buildLayout(provider, colorScheme)),
            );
          },
        ),
      ),
    );
  }

  Widget _buildLayout(BellScheduleProvider provider, ColorScheme cs) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide =
            constraints.maxWidth >= 900 &&
            MediaQuery.textScalerOf(context).scale(16) <= 22;
        final settings = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSectionHeader('Настройки', cs),
            const SizedBox(height: 12),
            _buildWeekScheduleSection(provider, cs),
            if (!provider.autoScheduleEnabled) ...[
              const SizedBox(height: 12),
              _buildPresetSelector(context, provider, cs),
            ],
            const SizedBox(height: 20),
            _buildTimeOffsetCard(provider, cs),
            if (provider.currentPresetId == 'custom' &&
                !provider.autoScheduleEnabled) ...[
              const SizedBox(height: 12),
              _buildResetButton(provider, cs),
            ],
          ],
        );
        final schedule = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildScheduleSectionHeader(provider, cs),
            const SizedBox(height: 12),
            _buildScheduleCard(provider, cs),
          ],
        );
        final padding = constraints.maxWidth < 600 ? 20.0 : 32.0;
        return SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: EdgeInsets.fromLTRB(padding, 20, padding, 32),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: wide ? 960 : 600),
              child: wide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(flex: 3, child: settings),
                        const SizedBox(width: 28),
                        Expanded(flex: 4, child: schedule),
                      ],
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        settings,
                        const SizedBox(height: 28),
                        schedule,
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }

  static const List<String> _weekdayNames = [
    'Пн',
    'Вт',
    'Ср',
    'Чт',
    'Пт',
    'Сб',
    'Вс',
  ];
  static const List<String> _weekdayFullNames = [
    'Понедельник',
    'Вторник',
    'Среда',
    'Четверг',
    'Пятница',
    'Суббота',
    'Воскресенье',
  ];

  Widget _buildWeekScheduleSection(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final today = DateTime.now().weekday; // 1=пн..7=вс

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.calendar_today_outlined,
                size: 20,
                color: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Автопереключение',
                      style: appFont(context, fontSize: 15, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'По дням недели',
                      style: appFont(context,
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Switch(
                value: provider.autoScheduleEnabled,
                onChanged: (value) {
                  HapticFeedback.lightImpact();
                  provider.setAutoScheduleEnabled(value);
                },
              ),
            ],
          ),
          // строки дней показываем только в автоматическом режиме
          if (provider.autoScheduleEnabled) ...[
            const SizedBox(height: 12),
            Divider(
              height: 1,
              color: colorScheme.outline.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 8),
            ...List.generate(6, (i) {
              final weekday = i + 1; // 1=пн..6=сб
              final isToday = weekday == today;
              final presetId = provider.weekdayPresets[weekday];
              final presetName = presetId != null
                  ? provider.presetNameForId(presetId)
                  : 'Не настроен';

              return Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      HapticFeedback.selectionClick();
                      _showWeekdayPresetPicker(provider, colorScheme, weekday);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      decoration: isToday
                          ? BoxDecoration(
                              color: colorScheme.tertiary.withValues(
                                alpha: 0.08,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: colorScheme.tertiary.withValues(
                                  alpha: 0.2,
                                ),
                              ),
                            )
                          : null,
                      child: Row(
                        children: [
                          SizedBox(
                            width: 28,
                            child: Text(
                              _weekdayNames[i],
                              style: appFont(context,
                                fontSize: 13,
                                fontWeight: isToday
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: isToday
                                    ? colorScheme.tertiary
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.6,
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              presetName,
                              style: appFont(context,
                                fontSize: 13,
                                color: presetId != null
                                    ? colorScheme.onSurface
                                    : colorScheme.onSurface.withValues(
                                        alpha: 0.35,
                                      ),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (isToday)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: colorScheme.tertiary.withValues(
                                  alpha: 0.15,
                                ),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                'сегодня',
                                style: appFont(context,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.tertiary,
                                ),
                              ),
                            ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: colorScheme.onSurface.withValues(
                              alpha: 0.25,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  void _showWeekdayPresetPicker(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
    int weekday,
  ) {
    final currentPresetId = provider.weekdayPresets[weekday];

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
                  _weekdayFullNames[weekday - 1],
                  style: appFont(ctx,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Выберите корпус',
                  style: appFont(ctx,
                    fontSize: 14,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 20),
                // вариант «не настроено»
                _buildWeekdayPresetOption(
                  ctx: ctx,
                  provider: provider,
                  colorScheme: colorScheme,
                  presetId: null,
                  name: 'Не настроен',
                  subtitle: 'Использовать ручной пресет',
                  isSelected: currentPresetId == null,
                  weekday: weekday,
                ),
                const SizedBox(height: 8),
                ...provider.allPresets.map((preset) {
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: _buildWeekdayPresetOption(
                      ctx: ctx,
                      provider: provider,
                      colorScheme: colorScheme,
                      presetId: preset.id,
                      name: preset.name,
                      subtitle: preset.isUserCreated
                          ? (preset.subtitle ?? 'Мой пресет')
                          : preset.subtitle,
                      isSelected: currentPresetId == preset.id,
                      weekday: weekday,
                      isUser: preset.isUserCreated,
                    ),
                  );
                }),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildWeekdayPresetOption({
    required BuildContext ctx,
    required BellScheduleProvider provider,
    required ColorScheme colorScheme,
    required String? presetId,
    required String name,
    required String? subtitle,
    required bool isSelected,
    required int weekday,
    bool isUser = false,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        provider.setWeekdayPreset(weekday, presetId);
        Navigator.pop(ctx);
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? colorScheme.tertiary.withValues(alpha: 0.1)
              : colorScheme.onSurface.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected
                ? colorScheme.tertiary.withValues(alpha: 0.3)
                : colorScheme.outline.withValues(alpha: 0.08),
            width: 1.5,
          ),
        ),
        child: Row(
          children: [
            if (isUser) ...[
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.person_outline_rounded,
                  size: 16,
                  color: colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 10),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: appFont(context,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: isSelected
                          ? colorScheme.tertiary
                          : colorScheme.onSurface,
                    ),
                  ),
                  if (subtitle != null)
                    Text(
                      subtitle,
                      style: appFont(context,
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                ],
              ),
            ),
            if (isSelected)
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color: colorScheme.tertiary,
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
    );
  }

  Widget _buildScheduleSectionHeader(
    BellScheduleProvider provider,
    ColorScheme cs,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSectionHeader('Расписание', cs),
        if (provider.autoScheduleEnabled) ...[
          const SizedBox(height: 6),
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Text(
              provider.effectivePresetName,
              style: appFont(context,
                fontSize: 13,
                height: 1.4,
                color: cs.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPresetSelector(
    BuildContext context,
    BellScheduleProvider provider,
    ColorScheme cs,
  ) {
    return AppInteractiveCard(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        leading: Icon(Icons.schedule_rounded, size: 20, color: cs.primary),
        title: Text(
          'Текущее расписание',
          style: appFont(context, fontSize: 13, color: cs.onSurfaceVariant),
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            provider.currentPresetName,
            style: appFont(context,
              fontSize: 15,
              height: 1.4,
              fontWeight: FontWeight.w500,
              color: cs.onSurface,
            ),
          ),
        ),
        trailing: Icon(
          Icons.expand_more_rounded,
          size: 20,
          color: cs.onSurfaceVariant,
        ),
        onTap: () {
          HapticFeedback.lightImpact();
          _showPresetPicker(provider, cs);
        },
      ),
    );
  }

  String _formatOffsetText(int seconds) {
    if (seconds == 0) return 'Звонок звенит вовремя';

    final absSeconds = seconds.abs();
    final mins = absSeconds ~/ 60;
    final secs = absSeconds % 60;

    String timeStr;
    if (mins > 0 && secs > 0) {
      timeStr = '$mins мин $secs сек';
    } else if (mins > 0) {
      timeStr = '$mins мин';
    } else {
      timeStr = '$secs сек';
    }

    if (seconds > 0) {
      return 'Звонок отстаёт на $timeStr';
    } else {
      return 'Звонок спешит на $timeStr';
    }
  }

  String _formatOffsetBadge(int seconds) {
    if (seconds == 0) return '0';

    final absSeconds = seconds.abs();
    final mins = absSeconds ~/ 60;
    final secs = absSeconds % 60;

    final sign = seconds > 0 ? '+' : '-';
    if (mins > 0 && secs > 0) {
      return '$sign$mins:${secs.toString().padLeft(2, '0')}';
    } else if (mins > 0) {
      return '$sign$mins:00';
    } else {
      return '$sign$secs сек';
    }
  }

  Widget _buildTimeOffsetCard(BellScheduleProvider provider, ColorScheme cs) {
    if (provider.usesServerTime) {
      return AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildSyncModeSelector(provider, cs),
            const SizedBox(height: 12),
            Text(
              _formatOffsetText(provider.timeOffset),
              style: appFont(context, fontSize: 14),
            ),
            const SizedBox(height: 8),
            Text(
              provider.syncStatus,
              style: appFont(context,
                fontSize: 13,
                height: 1.5,
                color: cs.onSurfaceVariant,
              ),
            ),
          ],
        ),
      );
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (provider.supportsServerSync) ...[
            _buildSyncModeSelector(provider, cs),
            const SizedBox(height: 16),
          ],
          Text(
            'Коррекция времени',
            style: appFont(context, fontSize: 15, fontWeight: FontWeight.w500),
          ),
          const SizedBox(height: 6),
          Text(
            _formatOffsetText(provider.timeOffset),
            style: appFont(context,
              fontSize: 13,
              height: 1.4,
              color: cs.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => _showOffsetEditor(provider, cs),
            icon: const Icon(Icons.tune_rounded, size: 18),
            label: Text(
              provider.timeOffset == 0
                  ? '0 сек'
                  : _formatOffsetBadge(provider.timeOffset),
              style: appFont(context, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(48, 56),
              side: BorderSide(color: cs.outline.withValues(alpha: 0.18)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) {
              final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
              final columns = constraints.maxWidth >= 280 * textScale ? 4 : 2;
              final buttonWidth =
                  (constraints.maxWidth - (columns - 1) * 8) / columns;
              return Wrap(
                alignment: WrapAlignment.center,
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final step in [
                    (-60, '−1 мин'),
                    (-10, '−10 сек'),
                    (10, '+10 сек'),
                    (60, '+1 мин'),
                  ])
                    SizedBox(
                      width: buttonWidth,
                      child: OutlinedButton(
                        onPressed: () {
                          HapticFeedback.selectionClick();
                          provider.setTimeOffset(provider.timeOffset + step.$1);
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(48, 48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 12,
                          ),
                          foregroundColor: cs.onSurfaceVariant,
                          side: BorderSide(
                            color: cs.outline.withValues(alpha: 0.18),
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                        child: Text(
                          step.$2,
                          style: appFont(context,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          TextButton.icon(
            onPressed: provider.timeOffset == 0
                ? null
                : () => provider.setTimeOffset(0),
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: Text('Сбросить коррекцию', style: appFont(context, fontSize: 13)),
          ),
        ],
      ),
    );
  }

  Widget _buildSyncModeSelector(BellScheduleProvider provider, ColorScheme cs) {
    return Material(
      color: Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Синхронизация звонков',
            style: appFont(context, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            provider.effectivePresetName,
            style: appFont(context, fontSize: 12, color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          for (final option in [
            (true, 'С сервера', 'Тайминги и точное время с reschool.app'),
            (false, 'Вручную', 'Своя коррекция для этого корпуса'),
          ])
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                provider.usesServerTime == option.$1
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: provider.usesServerTime == option.$1
                    ? cs.primary
                    : cs.onSurfaceVariant,
              ),
              title: Text(option.$2, style: appFont(context, fontSize: 14)),
              subtitle: Text(
                option.$3,
                style: appFont(context, fontSize: 12, color: cs.onSurfaceVariant),
              ),
              onTap: () => provider.setServerSync(option.$1),
            ),
        ],
      ),
    );
  }

  void _showOffsetEditor(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
  ) {
    final currentOffset = provider.timeOffset;
    final isNegative = currentOffset < 0;
    final absOffset = currentOffset.abs();
    final minsController = TextEditingController(
      text: (absOffset ~/ 60).toString(),
    );
    final secsController = TextEditingController(
      text: (absOffset % 60).toString(),
    );
    bool negative = isNegative;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: Text(
            'Коррекция времени',
            style: appFont(ctx, fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // переключатель направления
              Row(
                children: [
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => negative = false),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: !negative
                              ? colorScheme.primary.withValues(alpha: 0.1)
                              : colorScheme.onSurface.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: !negative
                                ? colorScheme.primary.withValues(alpha: 0.3)
                                : colorScheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Отстаёт',
                            style: appFont(ctx,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: !negative
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GestureDetector(
                      onTap: () => setDialogState(() => negative = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        decoration: BoxDecoration(
                          color: negative
                              ? colorScheme.primary.withValues(alpha: 0.1)
                              : colorScheme.onSurface.withValues(alpha: 0.03),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: negative
                                ? colorScheme.primary.withValues(alpha: 0.3)
                                : colorScheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Center(
                          child: Text(
                            'Спешит',
                            style: appFont(ctx,
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: negative
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ввод времени
              Row(
                children: [
                  Expanded(
                    child: _TimeTextField(
                      controller: minsController,
                      label: 'Минуты',
                      colorScheme: colorScheme,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _TimeTextField(
                      controller: secsController,
                      label: 'Секунды',
                      colorScheme: colorScheme,
                    ),
                  ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                'Отмена',
                style: appFont(ctx,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            FilledButton(
              onPressed: () {
                HapticFeedback.lightImpact();
                final mins = int.tryParse(minsController.text) ?? 0;
                final secs = int.tryParse(secsController.text) ?? 0;
                final totalSeconds = mins * 60 + secs;
                provider.setTimeOffset(negative ? -totalSeconds : totalSeconds);
                Navigator.pop(ctx);
              },
              style: FilledButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: Text(
                'Сохранить',
                style: appFont(ctx, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        title,
        style: appFont(context,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildScheduleCard(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedLessons = provider.sortedLessonNumbers;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: sortedLessons.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Нет уроков',
                  style: appFont(context,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          : Column(
              children: sortedLessons.asMap().entries.map((entry) {
                final lessonNum = entry.value;
                final isLast = entry.key == sortedLessons.length - 1;
                final time = provider.getLessonTime(
                  lessonNum,
                  applyOffset: provider.usesServerTime,
                );

                if (time == null) return const SizedBox.shrink();

                return Column(
                  children: [
                    _LessonRow(
                      lessonNum: lessonNum,
                      time: time,
                      colorScheme: colorScheme,
                      onTap: provider.usesServerTime
                          ? null
                          : () => _editLessonTime(
                              provider,
                              lessonNum,
                              time,
                              colorScheme,
                            ),
                    ),
                    if (!isLast)
                      Divider(
                        height: 1,
                        indent: 68,
                        color: colorScheme.outline.withValues(alpha: 0.08),
                      ),
                  ],
                );
              }).toList(),
            ),
    );
  }

  Widget _buildResetButton(BellScheduleProvider provider, ColorScheme cs) {
    return TextButton.icon(
      onPressed: () => _showResetDialog(provider, cs),
      icon: const Icon(Icons.restore_rounded, size: 18),
      label: Text(
        'Сбросить по умолчанию',
        style: appFont(context, fontSize: 13, fontWeight: FontWeight.w500),
      ),
      style: TextButton.styleFrom(
        foregroundColor: cs.error,
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  void _showPresetPicker(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
  ) {
    showModalBottomSheet(
      context: context,
      backgroundColor: colorScheme.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => _PresetPickerSheet(
        provider: provider,
        colorScheme: colorScheme,
        selectedId: provider.currentPresetId,
        onSelect: (id) {
          HapticFeedback.selectionClick();
          provider.applyPreset(id);
          Navigator.pop(ctx);
        },
        onCreateNew: () {
          Navigator.pop(ctx);
          showPresetEditScreen(context, provider);
        },
        onEdit: (preset) {
          Navigator.pop(ctx);
          showPresetEditScreen(context, provider, preset: preset);
        },
        onDelete: (preset) {
          Navigator.pop(ctx);
          _confirmDeletePreset(provider, colorScheme, preset);
        },
      ),
    );
  }

  Future<void> _confirmDeletePreset(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
    BellSchedulePreset preset,
  ) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Удалить пресет?',
          style: appFont(ctx, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Пресет «${preset.name}» будет удалён без возможности восстановления.',
          style: appFont(ctx, color: colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: appFont(ctx,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text('Удалить', style: appFont(ctx, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    if (confirm == true) {
      HapticFeedback.lightImpact();
      provider.deleteUserPreset(preset.id);
    }
  }

  Future<void> _editLessonTime(
    BellScheduleProvider provider,
    int lessonNum,
    LessonTime currentTime,
    ColorScheme colorScheme,
  ) async {
    final startController = TextEditingController(text: currentTime.start);
    final endController = TextEditingController(text: currentTime.end);

    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          '$lessonNum урок',
          style: appFont(ctx, fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.of(ctx).viewInsets.bottom > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface
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
                    onPressed: _dismissKeyboard,
                  ),
                ),
              ),
            _TimeTextField(
              controller: startController,
              label: 'Начало',
              colorScheme: colorScheme,
            ),
            const SizedBox(height: 16),
            _TimeTextField(
              controller: endController,
              label: 'Конец',
              colorScheme: colorScheme,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(
              'Отмена',
              style: appFont(ctx,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          FilledButton(
            onPressed: () {
              HapticFeedback.lightImpact();
              provider.setLessonTime(
                lessonNum,
                LessonTime(
                  start: startController.text,
                  end: endController.text,
                ),
              );
              Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Сохранить',
              style: appFont(ctx, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetDialog(
    BellScheduleProvider provider,
    ColorScheme colorScheme,
  ) async {
    HapticFeedback.lightImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Сбросить расписание?',
          style: appFont(ctx, fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Вернуть стандартное расписание звонков',
          style: appFont(ctx, color: colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: appFont(ctx,
                color: colorScheme.onSurface.withValues(alpha: 0.6),
              ),
            ),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: Text(
              'Сбросить',
              style: appFont(ctx, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      provider.resetToDefault();
    }
  }
}

class _LessonRow extends StatelessWidget {
  final int lessonNum;
  final LessonTime time;
  final ColorScheme colorScheme;
  final VoidCallback? onTap;

  const _LessonRow({
    required this.lessonNum,
    required this.time,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '$lessonNum',
                  textAlign: TextAlign.center,
                  style: appFont(context,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.primary,
                  ),
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$lessonNum урок',
                      style: appFont(context,
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${time.start} - ${time.end}',
                      style: appFont(context,
                        fontSize: 16,
                        height: 1.4,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (onTap != null)
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: colorScheme.onSurfaceVariant,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeTextField extends StatelessWidget {
  final TextEditingController controller;
  final String label;
  final ColorScheme colorScheme;

  const _TimeTextField({
    required this.controller,
    required this.label,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.done,
        onEditingComplete: () => FocusScope.of(context).unfocus(),
        style: appFont(context, fontSize: 16, color: colorScheme.onSurface),
        cursorColor: colorScheme.primary,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: appFont(context,
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          floatingLabelStyle: appFont(context, color: colorScheme.primary),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 16,
          ),
          prefixIcon: Icon(
            Icons.access_time_rounded,
            size: 20,
            color: colorScheme.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ),
    );
  }
}

// шторка выбора пресета, показывает и пользовательские

class _PresetPickerSheet extends StatefulWidget {
  final BellScheduleProvider provider;
  final ColorScheme colorScheme;
  final String selectedId;
  final ValueChanged<String> onSelect;
  final VoidCallback onCreateNew;
  final ValueChanged<BellSchedulePreset> onEdit;
  final ValueChanged<BellSchedulePreset> onDelete;

  const _PresetPickerSheet({
    required this.provider,
    required this.colorScheme,
    required this.selectedId,
    required this.onSelect,
    required this.onCreateNew,
    required this.onEdit,
    required this.onDelete,
  });

  @override
  State<_PresetPickerSheet> createState() => _PresetPickerSheetState();
}

class _PresetPickerSheetState extends State<_PresetPickerSheet> {
  ColorScheme get cs => widget.colorScheme;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final builtIn = BellScheduleProvider.presets;
    final userPresets = widget.provider.userPresets;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(
          children: [
            // полоска для перетаскивания и шапка
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
              child: Column(
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: cs.onSurface.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Text(
                        'Расписание звонков',
                        style: appFont(ctx,
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: widget.onCreateNew,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: cs.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.add_rounded,
                                size: 16,
                                color: cs.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'Создать',
                                style: appFont(ctx,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: cs.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            // список
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 32),
                children: [
                  _sheetSectionHeader('Встроенные'),
                  const SizedBox(height: 8),
                  ...builtIn.map(
                    (preset) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PresetTile(
                        preset: preset,
                        isSelected: widget.selectedId == preset.id,
                        colorScheme: cs,
                        isDark: isDark,
                        onTap: () => widget.onSelect(preset.id),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      _sheetSectionHeader('Мои пресеты'),
                      const Spacer(),
                      if (userPresets.isEmpty)
                        Text(
                          'ещё нет',
                          style: appFont(ctx,
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.3),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (userPresets.isEmpty)
                    _EmptyUserPresetsHint(
                      colorScheme: cs,
                      isDark: isDark,
                      onTap: widget.onCreateNew,
                    ),
                  ...userPresets.map(
                    (preset) => Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: _PresetTile(
                        preset: preset,
                        isSelected: widget.selectedId == preset.id,
                        colorScheme: cs,
                        isDark: isDark,
                        onTap: () => widget.onSelect(preset.id),
                        onEdit: () => widget.onEdit(preset),
                        onDelete: () => widget.onDelete(preset),
                      ),
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

  Widget _sheetSectionHeader(String text) {
    return Text(
      text.toUpperCase(),
      style: appFont(context,
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.8,
        color: cs.onSurface.withValues(alpha: 0.4),
      ),
    );
  }
}

class _PresetTile extends StatelessWidget {
  final BellSchedulePreset preset;
  final bool isSelected;
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  const _PresetTile({
    required this.preset,
    required this.isSelected,
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
    this.onEdit,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    final isUser = preset.isUserCreated;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      decoration: BoxDecoration(
        color: isSelected
            ? cs.primary.withValues(alpha: 0.08)
            : isDark
            ? cs.onSurface.withValues(alpha: 0.04)
            : cs.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isSelected
              ? cs.primary.withValues(alpha: 0.28)
              : cs.outline.withValues(alpha: 0.08),
          width: 1.5,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(15),
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isUser
                        ? cs.secondary.withValues(alpha: 0.12)
                        : cs.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    isUser
                        ? Icons.person_outline_rounded
                        : Icons.school_outlined,
                    size: 20,
                    color: isUser ? cs.secondary : cs.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        preset.name,
                        style: appFont(context,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? cs.primary : cs.onSurface,
                        ),
                      ),
                      if (preset.subtitle != null)
                        Text(
                          preset.subtitle!,
                          style: appFont(context,
                            fontSize: 13,
                            color: cs.onSurface.withValues(alpha: 0.5),
                          ),
                        )
                      else if (isUser)
                        Text(
                          '${preset.lessons.length} уроков',
                          style: appFont(context,
                            fontSize: 12,
                            color: cs.onSurface.withValues(alpha: 0.4),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isUser) ...[
                  _iconBtn(
                    icon: Icons.edit_outlined,
                    color: cs.secondary,
                    onTap: onEdit!,
                  ),
                  const SizedBox(width: 4),
                  _iconBtn(
                    icon: Icons.delete_outline_rounded,
                    color: cs.error,
                    onTap: onDelete!,
                  ),
                  const SizedBox(width: 4),
                ],
                if (isSelected)
                  Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      color: cs.primary,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  )
                else
                  const SizedBox(width: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _iconBtn({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        onTap();
      },
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, size: 16, color: color),
      ),
    );
  }
}

class _EmptyUserPresetsHint extends StatelessWidget {
  final ColorScheme colorScheme;
  final bool isDark;
  final VoidCallback onTap;

  const _EmptyUserPresetsHint({
    required this.colorScheme,
    required this.isDark,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(20),
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: isDark
              ? cs.primary.withValues(alpha: 0.04)
              : cs.primary.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cs.primary.withValues(alpha: 0.12)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: cs.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(Icons.add_rounded, size: 22, color: cs.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Создать свой пресет',
                    style: appFont(context,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  Text(
                    'Настройте расписание для своей школы',
                    style: appFont(context,
                      fontSize: 12,
                      color: cs.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.chevron_right_rounded,
              size: 20,
              color: cs.primary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
