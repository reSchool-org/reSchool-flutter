import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../models/lesson_view_model.dart';
import '../models/custom_homework.dart';
import '../providers/custom_homework_provider.dart';
import '../providers/settings_provider.dart';
import '../screens/homework_detail_screen.dart';
import '../utils/time_utils.dart';
import '../utils/teacher_chat.dart';
import 'timer_progress_widget.dart';
import 'custom_homework_card.dart';
import 'homework_summary_card.dart';
import 'homework_analysis_card.dart';
import 'custom_homework_dialog.dart';
import '../utils/app_font.dart';
import '../utils/mark_color.dart';

class LessonCard extends StatelessWidget {
  final LessonViewModel lesson;
  final VoidCallback onTap;
  final bool isNow;
  final bool isDesktop;
  final int customHomeworkCount;

  const LessonCard({
    super.key,
    required this.lesson,
    required this.onTap,
    this.isNow = false,
    this.isDesktop = false,
    this.customHomeworkCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final cloudHomeworkEnabled = context
        .watch<SettingsProvider>()
        .cloudHomeworkEnabled;

    if (lesson.isPlaceholder) {
      return _buildPlaceholderCard(context, colorScheme, isDark);
    }

    final horizontalMargin = isDesktop ? 8.0 : 20.0;
    final verticalMargin = isDesktop ? 6.0 : 6.0;

    return Container(
      margin: EdgeInsets.symmetric(
        horizontal: horizontalMargin,
        vertical: verticalMargin,
      ),
      decoration: BoxDecoration(
        color: isNow
            ? colorScheme.primary.withValues(alpha: 0.08)
            : isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 16),
        border: Border.all(
          color: isNow
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.08),
          width: isNow ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(isDesktop ? 18 : 16),
          child: Padding(
            padding: EdgeInsets.all(isDesktop ? 18 : 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // номер урока и время
                Column(
                  children: [
                    Container(
                      width: isDesktop ? 44 : 36,
                      height: isDesktop ? 44 : 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isNow
                            ? colorScheme.primary
                            : colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(
                          isDesktop ? 12 : 10,
                        ),
                      ),
                      child: Text(
                        lesson.num.toString(),
                        style: appFont(context,
                          fontSize: isDesktop ? 18 : 16,
                          fontWeight: FontWeight.w600,
                          color: isNow ? Colors.white : colorScheme.primary,
                        ),
                      ),
                    ),
                    if (lesson.startTime.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        TimeUtils.formatForDisplay(lesson.startTime),
                        style: appFont(context,
                          fontSize: isDesktop ? 12 : 11,
                          fontWeight: isNow ? FontWeight.w600 : FontWeight.w500,
                          color: isNow
                              ? colorScheme.primary
                              : colorScheme.onSurface.withValues(alpha: 0.4),
                        ),
                      ),
                    ],
                    if (isDesktop && lesson.endTime.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        TimeUtils.formatForDisplay(lesson.endTime),
                        style: appFont(context,
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.3),
                        ),
                      ),
                    ],
                  ],
                ),
                SizedBox(width: isDesktop ? 18 : 14),

                // содержимое
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // предмет и оценка
                      Row(
                        children: [
                          Expanded(
                            child: Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    lesson.subject,
                                    style: appFont(context,
                                      fontSize: isDesktop ? 16 : 15,
                                      fontWeight: FontWeight.w600,
                                      color: isNow
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                // значок своего домашнего задания
                                if (cloudHomeworkEnabled &&
                                    customHomeworkCount > 0) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colorScheme.tertiary.withValues(
                                        alpha: 0.15,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.edit_note_rounded,
                                          size: 12,
                                          color: colorScheme.tertiary,
                                        ),
                                        const SizedBox(width: 2),
                                        Text(
                                          '$customHomeworkCount',
                                          style: appFont(context,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.tertiary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (lesson.mark != null) ...[
                            const SizedBox(width: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _getMarkColor(lesson.mark!)
                                    .withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                lesson.mark!,
                                style: appFont(context,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: _getMarkColor(lesson.mark!),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),

                      // тема
                      if (lesson.topic.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Text(
                          lesson.topic,
                          style: appFont(context,
                            fontSize: 13,
                            color: colorScheme.onSurface.withValues(alpha: 0.6),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],

                      // учитель
                      if (lesson.teacher.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Builder(
                          builder: (context) {
                            final chatEnabled = context
                                .watch<SettingsProvider>()
                                .teacherChatEnabled;
                            final canChat =
                                chatEnabled && lesson.teacherFull.isNotEmpty;
                            return GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTap: canChat
                                  ? () => openChatWithTeacher(
                                      context,
                                      lesson.teacherFull,
                                    )
                                  : null,
                              child: Row(
                                children: [
                                  Icon(
                                    Icons.person_outline_rounded,
                                    size: 14,
                                    color: colorScheme.onSurface.withValues(
                                      alpha: 0.4,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      lesson.teacher,
                                      style: appFont(context,
                                        fontSize: 12,
                                        color: colorScheme.onSurface.withValues(
                                          alpha: 0.5,
                                        ),
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (canChat)
                                    Icon(
                                      Icons.chat_bubble_outline_rounded,
                                      size: 12,
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.45,
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],

                      // таймер идущего урока
                      if (isNow &&
                          lesson.startTime.isNotEmpty &&
                          lesson.endTime.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        TimerProgressWidget(
                          startTime: lesson.startTime,
                          endTime: lesson.endTime,
                          label: l10n.lessonEnd,
                        ),
                      ],

                      // домашнее задание
                      if (lesson.homework.isNotEmpty ||
                          (lesson.homeworkHtml?.isNotEmpty ?? false) ||
                          lesson.homeworkFiles.isNotEmpty ||
                          (lesson.homeworkAttachCount ?? 0) > 0) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: Colors.amber.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.assignment_outlined,
                                size: 16,
                                color: Colors.amber[800],
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  (() {
                                    final attachmentCount =
                                        lesson.homeworkFiles.isNotEmpty
                                        ? lesson.homeworkFiles.length
                                        : (lesson.homeworkAttachCount ?? 0);
                                    return attachmentCount > 0
                                        ? l10n.homeworkWithFiles(
                                            attachmentCount,
                                          )
                                        : l10n.homeworkLabel;
                                  })(),
                                  style: appFont(context,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: Colors.amber[900],
                                  ),
                                ),
                              ),
                              Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: Colors.amber[700],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPlaceholderCard(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final horizontalMargin = isDesktop ? 8.0 : 20.0;
    final hasTimer =
        isNow && lesson.startTime.isNotEmpty && lesson.endTime.isNotEmpty;

    return Container(
      margin: EdgeInsets.symmetric(horizontal: horizontalMargin, vertical: 6),
      padding: EdgeInsets.all(isDesktop ? 18 : 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(isDesktop ? 18 : 16),
        border: Border.all(
          color: isNow
              ? colorScheme.primary.withValues(alpha: 0.3)
              : colorScheme.outline.withValues(alpha: 0.15),
          width: isNow ? 1.5 : 1,
        ),
        color: isNow
            ? colorScheme.primary.withValues(alpha: 0.06)
            : isDark
            ? colorScheme.onSurface.withValues(alpha: 0.02)
            : colorScheme.onSurface.withValues(alpha: 0.01),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: isDesktop ? 44 : 36,
                height: isDesktop ? 44 : 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isNow
                      ? colorScheme.primary.withValues(alpha: 0.12)
                      : colorScheme.outline.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(isDesktop ? 12 : 10),
                ),
                child: Text(
                  lesson.num.toString(),
                  style: appFont(context,
                    fontSize: isDesktop ? 18 : 16,
                    fontWeight: FontWeight.w600,
                    color: isNow
                        ? colorScheme.primary.withValues(alpha: 0.8)
                        : colorScheme.outline.withValues(alpha: 0.5),
                  ),
                ),
              ),
              SizedBox(width: isDesktop ? 18 : 14),
              Icon(
                Icons.help_outline_rounded,
                size: isDesktop ? 20 : 18,
                color: isNow
                    ? colorScheme.primary.withValues(alpha: 0.5)
                    : colorScheme.outline.withValues(alpha: 0.4),
              ),
              const SizedBox(width: 8),
              Text(
                lesson.subject,
                style: appFont(context,
                  fontSize: isDesktop ? 15 : 14,
                  fontStyle: FontStyle.italic,
                  color: isNow
                      ? colorScheme.primary.withValues(alpha: 0.7)
                      : colorScheme.outline.withValues(alpha: 0.5),
                ),
              ),
              const Spacer(),
              if (lesson.startTime.isNotEmpty)
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      TimeUtils.formatForDisplay(lesson.startTime),
                      style: appFont(context,
                        fontSize: isDesktop ? 13 : 12,
                        fontWeight: isNow ? FontWeight.w600 : FontWeight.w400,
                        color: isNow
                            ? colorScheme.primary
                            : colorScheme.outline.withValues(alpha: 0.4),
                      ),
                    ),
                    if (lesson.endTime.isNotEmpty)
                      Text(
                        TimeUtils.formatForDisplay(lesson.endTime),
                        style: appFont(context,
                          fontSize: 10,
                          color: isNow
                              ? colorScheme.primary.withValues(alpha: 0.5)
                              : colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                  ],
                ),
            ],
          ),
          if (hasTimer) ...[
            const SizedBox(height: 12),
            TimerProgressWidget(
              startTime: lesson.startTime,
              endTime: lesson.endTime,
              label: l10n.lessonEnd,
            ),
          ],
        ],
      ),
    );
  }

  Color _getMarkColor(String mark) => colorForMark(mark);
}

class LessonDetailSheet extends StatefulWidget {
  final LessonViewModel lesson;
  final DateTime? lessonDate;

  const LessonDetailSheet({super.key, required this.lesson, this.lessonDate});

  @override
  State<LessonDetailSheet> createState() => _LessonDetailSheetState();
}

class _LessonDetailSheetState extends State<LessonDetailSheet> {
  @override
  void initState() {
    super.initState();
    _loadCustomHomework();
  }

  void _loadCustomHomework() {
    if (!context.read<SettingsProvider>().cloudHomeworkEnabled) return;

    if (widget.lessonDate != null &&
        context.read<SettingsProvider>().cloudEnabled) {
      // начало недели, то есть понедельник
      final date = widget.lessonDate!;
      final weekday = date.weekday;
      final weekStart = date.subtract(Duration(days: weekday - 1));

      // грузим домашнее задание на эту неделю
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          context.read<CustomHomeworkProvider>().loadHomeworkForWeek(weekStart);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final l10n = AppLocalizations.of(context)!;
    final cloudHomeworkEnabled = context
        .watch<SettingsProvider>()
        .cloudHomeworkEnabled;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
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
                    // предмет
                    Text(
                      widget.lesson.subject,
                      style: appFont(context,
                        fontSize: 26,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      l10n.lessonHeader(
                        widget.lesson.num,
                        TimeUtils.formatForDisplay(widget.lesson.startTime),
                        TimeUtils.formatForDisplay(widget.lesson.endTime),
                      ),
                      style: appFont(context,
                        fontSize: 14,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // карточки с деталями
                    _buildInfoCard(
                      icon: Icons.person_outline_rounded,
                      label: l10n.lessonTeacher,
                      value: widget.lesson.teacherFull,
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),
                    const SizedBox(height: 12),
                    _buildInfoCard(
                      icon: Icons.topic_outlined,
                      label: l10n.lessonTopic,
                      value: widget.lesson.topic,
                      colorScheme: colorScheme,
                      isDark: isDark,
                    ),

                    // оценка
                    if (widget.lesson.mark != null) ...[
                      const SizedBox(height: 24),
                      _buildMarkCard(colorScheme, isDark, l10n),
                    ],

                    // домашнее задание
                    if (widget.lesson.homework.isNotEmpty ||
                        (widget.lesson.homeworkHtml?.isNotEmpty ?? false) ||
                        widget.lesson.homeworkFiles.isNotEmpty ||
                        (widget.lesson.homeworkAttachCount ?? 0) > 0) ...[
                      const SizedBox(height: 24),
                      _buildHomeworkSection(context, colorScheme, isDark, l10n),
                      if (widget.lessonDate != null &&
                          widget.lesson.homework.trim().isNotEmpty) ...[
                        const SizedBox(height: 12),
                        HomeworkAnalysisCard(
                          subject: widget.lesson.subject,
                          date: widget.lessonDate,
                          text: widget.lesson.homework,
                          onAttachMaterial: () =>
                              _showAddHomeworkDialog(context),
                        ),
                      ],
                    ],

                    // блок своего домашнего задания
                    if (cloudHomeworkEnabled && widget.lessonDate != null) ...[
                      const SizedBox(height: 24),
                      _buildCustomHomeworkSection(
                        context,
                        colorScheme,
                        isDark,
                        l10n,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCustomHomeworkSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    return Consumer<CustomHomeworkProvider>(
      builder: (context, provider, _) {
        final customHomework = widget.lessonDate != null
            ? provider.getHomeworkForSubjectAndDate(
                widget.lesson.subject,
                widget.lessonDate!,
              )
            : <CustomHomework>[];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // шапка
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  l10n.customHomework.toUpperCase(),
                  style: appFont(context,
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.0,
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
                if (widget.lessonDate != null)
                  GestureDetector(
                    onTap: () => _showAddHomeworkDialog(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.add_rounded,
                            size: 14,
                            color: colorScheme.primary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            l10n.addCustomHomework,
                            style: appFont(context,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(height: 10),

            // сводка урока, если записей больше одной
            if (widget.lessonDate != null) ...[
              HomeworkSummaryCard(
                subject: widget.lesson.subject,
                date: widget.lessonDate!,
              ),
              const SizedBox(height: 10),
            ],

            // загрузка
            if (provider.isLoading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary.withValues(alpha: 0.5),
                    ),
                  ),
                ),
              )
            // список домашних заданий
            else if (customHomework.isNotEmpty)
              ...customHomework.map(
                (hw) => Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: CustomHomeworkCard(
                    homework: hw,
                    onDeleted: () => setState(() {}),
                  ),
                ),
              )
            // пусто
            else
              Container(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.edit_note_rounded,
                      size: 16,
                      color: colorScheme.onSurface.withValues(alpha: 0.25),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      l10n.noCustomHomework,
                      style: appFont(context,
                        fontSize: 13,
                        color: colorScheme.onSurface.withValues(alpha: 0.3),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }

  void _showAddHomeworkDialog(BuildContext context) {
    if (widget.lessonDate == null) return;

    HapticFeedback.lightImpact();
    showDialog(
      context: context,
      builder: (ctx) => CustomHomeworkDialog(
        subject: widget.lesson.subject,
        lessonDate: widget.lessonDate!,
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required ColorScheme colorScheme,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.onSurface.withValues(alpha: 0.05)
            : colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, size: 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: appFont(context,
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  value.isEmpty ? "-" : value,
                  style: appFont(context,
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarkCard(
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    final markColor = _getMarkColor(widget.lesson.mark!);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: markColor.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: markColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: markColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Center(
              child: Text(
                widget.lesson.mark!,
                style: appFont(context,
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: markColor,
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
                  l10n.markLabel,
                  style: appFont(context,
                    fontSize: 12,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (widget.lesson.markDescription != null)
                  Text(
                    widget.lesson.markDescription!,
                    style: appFont(context,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: colorScheme.onSurface,
                    ),
                  ),
                if (widget.lesson.markWeight != null)
                  Text(
                    l10n.markWeight(widget.lesson.markWeight!),
                    style: appFont(context,
                      fontSize: 12,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHomeworkSection(
    BuildContext context,
    ColorScheme colorScheme,
    bool isDark,
    AppLocalizations l10n,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 12),
          child: Text(
            l10n.homeworkCaps,
            style: appFont(context,
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
        GestureDetector(
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => HomeworkDetailScreen(
                  subject: widget.lesson.subject,
                  text: widget.lesson.homework,
                  html: widget.lesson.homeworkHtml,
                  deadline: widget.lesson.homeworkDeadline,
                  files: widget.lesson.homeworkFiles,
                  partId: widget.lesson.homeworkPartId,
                  lessonDate: widget.lessonDate,
                ),
              ),
            );
          },
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.2)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.lesson.homework.isNotEmpty)
                  Text(
                    widget.lesson.homework,
                    style: appFont(context,
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.8),
                    ),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                  ),
                if ((widget.lesson.homeworkFiles.isNotEmpty
                        ? widget.lesson.homeworkFiles.length
                        : (widget.lesson.homeworkAttachCount ?? 0)) >
                    0) ...[
                  if (widget.lesson.homework.isNotEmpty)
                    const SizedBox(height: 12),
                  Row(
                    children: [
                      Icon(
                        Icons.attach_file_rounded,
                        size: 16,
                        color: Colors.amber[800],
                      ),
                      const SizedBox(width: 6),
                      Text(
                        (() {
                          final attachmentCount =
                              widget.lesson.homeworkFiles.isNotEmpty
                              ? widget.lesson.homeworkFiles.length
                              : (widget.lesson.homeworkAttachCount ?? 0);
                          return l10n.filesCount(attachmentCount);
                        })(),
                        style: appFont(context,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber[800],
                        ),
                      ),
                      const Spacer(),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 14,
                        color: Colors.amber[700],
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Color _getMarkColor(String mark) => colorForMark(mark);
}
