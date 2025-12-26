import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import '../providers/bell_schedule_provider.dart';
import '../widgets/responsive_layout.dart';

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
          centerTitle: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back_rounded, color: colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text(
            'Звонки',
            style: GoogleFonts.inter(
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
              child: Center(
                child: ConstrainedBox(
                  constraints:
                      BoxConstraints(maxWidth: isDesktop(context) ? 600.0 : double.infinity),
                  child: ListView(
                    keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      const SizedBox(height: 8),

                      _buildPresetSelector(provider, colorScheme),

                      const SizedBox(height: 16),

                      _buildTimeOffsetCard(provider, colorScheme),

                      const SizedBox(height: 24),

                      _buildSectionHeader('Расписание', colorScheme),
                      const SizedBox(height: 12),
                      _buildScheduleCard(provider, colorScheme),

                      const SizedBox(height: 20),

                      if (provider.currentPresetId == 'custom')
                        _buildResetButton(provider, colorScheme),

                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildPresetSelector(
      BellScheduleProvider provider, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showPresetPicker(provider, colorScheme);
      },
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              colorScheme.primary,
              colorScheme.primary.withValues(alpha: 0.8),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Icon(
                Icons.schedule_rounded,
                color: Colors.white,
                size: 22,
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Текущий пресет',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      color: Colors.white.withValues(alpha: 0.7),
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    provider.currentPresetName,
                    style: GoogleFonts.inter(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(
                Icons.keyboard_arrow_down_rounded,
                color: Colors.white,
                size: 20,
              ),
            ),
          ],
        ),
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

  Widget _buildTimeOffsetCard(
      BellScheduleProvider provider, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.secondary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.timer_outlined,
                  size: 20,
                  color: colorScheme.secondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Коррекция времени',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      _formatOffsetText(provider.timeOffset),
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              GestureDetector(
                onTap: () => _showOffsetEditor(provider, colorScheme),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: colorScheme.secondary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _formatOffsetBadge(provider.timeOffset),
                        style: GoogleFonts.inter(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.secondary,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.edit_outlined,
                        size: 14,
                        color: colorScheme.secondary,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildOffsetButton(provider, colorScheme, -60, '-1 мин'),
              const SizedBox(width: 8),
              _buildOffsetButton(provider, colorScheme, -10, '-10 сек'),
              const SizedBox(width: 8),
              _buildResetOffsetButton(provider, colorScheme),
              const SizedBox(width: 8),
              _buildOffsetButton(provider, colorScheme, 10, '+10 сек'),
              const SizedBox(width: 8),
              _buildOffsetButton(provider, colorScheme, 60, '+1 мин'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOffsetButton(BellScheduleProvider provider, ColorScheme colorScheme, int delta, String label) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.selectionClick();
        provider.setTimeOffset(provider.timeOffset + delta);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  Widget _buildResetOffsetButton(BellScheduleProvider provider, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        provider.setTimeOffset(0);
      },
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: provider.timeOffset == 0
              ? colorScheme.onSurface.withValues(alpha: 0.05)
              : colorScheme.secondary.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          Icons.refresh_rounded,
          size: 18,
          color: provider.timeOffset == 0
              ? colorScheme.onSurface.withValues(alpha: 0.3)
              : colorScheme.secondary,
        ),
      ),
    );
  }

  void _showOffsetEditor(BellScheduleProvider provider, ColorScheme colorScheme) {
    final currentOffset = provider.timeOffset;
    final isNegative = currentOffset < 0;
    final absOffset = currentOffset.abs();
    final minsController = TextEditingController(text: (absOffset ~/ 60).toString());
    final secsController = TextEditingController(text: (absOffset % 60).toString());
    bool negative = isNegative;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Коррекция времени',
            style: GoogleFonts.inter(fontWeight: FontWeight.w600),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

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
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: !negative ? colorScheme.primary : colorScheme.onSurface,
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
                            style: GoogleFonts.inter(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: negative ? colorScheme.primary : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),

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
                style: GoogleFonts.inter(
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
                style: GoogleFonts.inter(fontWeight: FontWeight.w500),
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
        title.toUpperCase(),
        style: GoogleFonts.inter(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
          color: colorScheme.onSurface.withValues(alpha: 0.4),
        ),
      ),
    );
  }

  Widget _buildScheduleCard(
      BellScheduleProvider provider, ColorScheme colorScheme) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sortedLessons = provider.sortedLessonNumbers;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.08),
        ),
      ),
      child: sortedLessons.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(32),
              child: Center(
                child: Text(
                  'Нет уроков',
                  style: GoogleFonts.inter(
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ),
            )
          : Column(
              children: sortedLessons.asMap().entries.map((entry) {
                final lessonNum = entry.value;
                final isLast = entry.key == sortedLessons.length - 1;
                final time =
                    provider.getLessonTime(lessonNum, applyOffset: false);

                if (time == null) return const SizedBox.shrink();

                return Column(
                  children: [
                    _LessonRow(
                      lessonNum: lessonNum,
                      time: time,
                      colorScheme: colorScheme,
                      onTap: () => _editLessonTime(provider, lessonNum, time, colorScheme),
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

  Widget _buildResetButton(
      BellScheduleProvider provider, ColorScheme colorScheme) {
    return GestureDetector(
      onTap: () => _showResetDialog(provider, colorScheme),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: colorScheme.error.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.error.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.restore_rounded,
              size: 18,
              color: colorScheme.error,
            ),
            const SizedBox(width: 8),
            Text(
              'Сбросить по умолчанию',
              style: GoogleFonts.inter(
                fontSize: 14,
                fontWeight: FontWeight.w500,
                color: colorScheme.error,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showPresetPicker(
      BellScheduleProvider provider, ColorScheme colorScheme) {
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
                  'Выберите расписание',
                  style: GoogleFonts.inter(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 20),

                ...BellScheduleProvider.presets.map((preset) {
                  final isSelected = provider.currentPresetId == preset.id;

                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: GestureDetector(
                      onTap: () {
                        HapticFeedback.selectionClick();
                        provider.applyPreset(preset.id);
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
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    preset.name,
                                    style: GoogleFonts.inter(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: isSelected
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                  ),
                                  if (preset.subtitle != null)
                                    Text(
                                      preset.subtitle!,
                                      style: GoogleFonts.inter(
                                        fontSize: 13,
                                        color: colorScheme.onSurface
                                            .withValues(alpha: 0.5),
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
        );
      },
    );
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
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (MediaQuery.of(ctx).viewInsets.bottom > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
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
              style: GoogleFonts.inter(
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
                    start: startController.text, end: endController.text),
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _showResetDialog(
      BellScheduleProvider provider, ColorScheme colorScheme) async {
    HapticFeedback.lightImpact();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Сбросить расписание?',
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          'Вернуть стандартное расписание звонков',
          style: GoogleFonts.inter(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(
              'Отмена',
              style: GoogleFonts.inter(
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
              style: GoogleFonts.inter(fontWeight: FontWeight.w500),
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
  final VoidCallback onTap;

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
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Center(
                  child: Text(
                    '$lessonNum',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '$lessonNum урок',
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '${time.start} — ${time.end}',
                      style: GoogleFonts.inter(
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: colorScheme.primary,
                ),
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
        border: Border.all(
          color: colorScheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.datetime,
        textInputAction: TextInputAction.done,
        onEditingComplete: () => FocusScope.of(context).unfocus(),
        style: GoogleFonts.inter(
          fontSize: 16,
          color: colorScheme.onSurface,
        ),
        cursorColor: colorScheme.primary,
        decoration: InputDecoration(
          labelText: label,
          labelStyle: GoogleFonts.inter(
            color: colorScheme.onSurface.withValues(alpha: 0.5),
          ),
          floatingLabelStyle: GoogleFonts.inter(
            color: colorScheme.primary,
          ),
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