import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_homework.dart';
import '../providers/custom_homework_provider.dart';
import 'custom_homework_dialog.dart';
import 'homework_analysis_card.dart';
import '../utils/app_font.dart';

class CustomHomeworkCard extends StatelessWidget {
  final CustomHomework homework;
  final VoidCallback? onDeleted;

  const CustomHomeworkCard({
    super.key,
    required this.homework,
    this.onDeleted,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.6)
            : colorScheme.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // строка с автором
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 0),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.person_rounded,
                    size: 13,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    homework.authorFullName,
                    style: appFont(context,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (homework.isMine) ...[
                  _ActionIcon(
                    icon: Icons.edit_rounded,
                    onTap: () => _showEditDialog(context),
                    colorScheme: colorScheme,
                  ),
                  const SizedBox(width: 2),
                  _ActionIcon(
                    icon: Icons.delete_outline_rounded,
                    onTap: () => _showDeleteConfirmation(context, l10n),
                    colorScheme: colorScheme,
                    isDestructive: true,
                  ),
                ],
              ],
            ),
          ),

          // разделитель
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Divider(
              height: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),

          // текст
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
            child: Text(
              homework.text,
              style: appFont(context,
                fontSize: 14,
                height: 1.5,
                color: colorScheme.onSurface,
              ),
            ),
          ),

          // файлы
          if (homework.files.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: homework.files
                    .map((f) => _FileChip(file: f, colorScheme: colorScheme))
                    .toList(),
              ),
            ),
          ],

          // разбор с оценкой времени, если сервер его посчитал
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
            child: HomeworkAnalysisCard(
              key: ValueKey('${homework.id}:${homework.updatedAt}:${homework.text}'),
              subject: homework.subject,
              date: homework.lessonDate,
              text: homework.text,
              compact: true,
              showRejection: homework.isMine,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => CustomHomeworkDialog(
        subject: homework.subject,
        lessonDate: homework.lessonDate,
        existingHomework: homework,
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context, AppLocalizations l10n) {
    final colorScheme = Theme.of(context).colorScheme;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(l10n.deleteHomeworkQuestion, style: appFont(ctx, fontWeight: FontWeight.w600)),
        content: Text(
          l10n.deleteHomeworkWarning,
          style: appFont(ctx, color: colorScheme.onSurface.withValues(alpha: 0.7)),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel, style: appFont(ctx)),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _deleteHomework(context, l10n);
            },
            style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
            child: Text(l10n.delete, style: appFont(ctx)),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteHomework(BuildContext context, AppLocalizations l10n) async {
    final provider = context.read<CustomHomeworkProvider>();
    final success = await provider.deleteHomework(
      homeworkId: homework.id,
      subject: homework.subject,
      lessonDate: homework.lessonDate,
    );
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(success ? l10n.homeworkDeleted : l10n.error, style: appFont(context))),
      );
      if (success) onDeleted?.call();
    }
  }
}

class _ActionIcon extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;
  final bool isDestructive;

  const _ActionIcon({
    required this.icon,
    required this.onTap,
    required this.colorScheme,
    this.isDestructive = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: isDestructive
              ? colorScheme.error.withValues(alpha: 0.08)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(
          icon,
          size: 15,
          color: isDestructive
              ? colorScheme.error.withValues(alpha: 0.7)
              : colorScheme.onSurface.withValues(alpha: 0.35),
        ),
      ),
    );
  }
}

class _FileChip extends StatelessWidget {
  final CustomHomeworkFile file;
  final ColorScheme colorScheme;

  const _FileChip({required this.file, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => _downloadAndOpen(context),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.15),
            width: 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_fileIcon(file.fileName), size: 13, color: colorScheme.primary),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                file.fileName,
                style: appFont(context, fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              file.formattedSize,
              style: appFont(context, fontSize: 10, color: colorScheme.onSurface.withValues(alpha: 0.4)),
            ),
          ],
        ),
      ),
    );
  }

  IconData _fileIcon(String name) {
    final ext = name.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf': return Icons.picture_as_pdf_rounded;
      case 'doc': case 'docx': return Icons.description_rounded;
      case 'xls': case 'xlsx': return Icons.table_chart_rounded;
      case 'ppt': case 'pptx': return Icons.slideshow_rounded;
      case 'jpg': case 'jpeg': case 'png': case 'gif': return Icons.image_rounded;
      case 'zip': case 'rar': return Icons.folder_zip_rounded;
      default: return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _downloadAndOpen(BuildContext context) async {
    final provider = context.read<CustomHomeworkProvider>();
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.loading}...', style: appFont(context))),
    );

    final downloaded = await provider.downloadFile(fileId: file.id, fileName: file.fileName);
    if (downloaded != null) {
      await OpenFilex.open(downloaded.path);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.error, style: appFont(context))),
      );
    }
  }
}
