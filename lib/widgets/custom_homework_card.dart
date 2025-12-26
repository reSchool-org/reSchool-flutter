import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:open_filex/open_filex.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_homework.dart';
import '../providers/custom_homework_provider.dart';
import 'custom_homework_dialog.dart';

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

    return Container(
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colorScheme.primaryContainer.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [

          Row(
            children: [
              Icon(
                Icons.person_rounded,
                size: 14,
                color: colorScheme.primary,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  homework.authorFullName,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (homework.isMine) ...[
                _buildActionButton(
                  icon: Icons.edit_rounded,
                  onTap: () => _showEditDialog(context),
                  colorScheme: colorScheme,
                ),
                const SizedBox(width: 4),
                _buildActionButton(
                  icon: Icons.delete_rounded,
                  onTap: () => _showDeleteConfirmation(context, l10n),
                  colorScheme: colorScheme,
                  isDestructive: true,
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),

          Text(
            homework.text,
            style: GoogleFonts.inter(
              fontSize: 14,
              height: 1.4,
              color: colorScheme.onSurface,
            ),
          ),

          if (homework.files.isNotEmpty) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: homework.files.map((file) {
                return _buildFileChip(context, file, colorScheme);
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        onTap();
      },
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.all(6),
        decoration: BoxDecoration(
          color: isDestructive
              ? colorScheme.errorContainer.withValues(alpha: 0.3)
              : colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Icon(
          icon,
          size: 14,
          color: isDestructive ? colorScheme.error : colorScheme.onSurface.withValues(alpha: 0.6),
        ),
      ),
    );
  }

  Widget _buildFileChip(BuildContext context, CustomHomeworkFile file, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _downloadAndOpenFile(context, file),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _getFileIcon(file.fileName),
              size: 14,
              color: colorScheme.primary,
            ),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                file.fileName,
                style: GoogleFonts.inter(
                  fontSize: 11,
                  color: colorScheme.onSurface,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Text(
              file.formattedSize,
              style: GoogleFonts.inter(
                fontSize: 10,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = fileName.split('.').last.toLowerCase();
    switch (ext) {
      case 'pdf':
        return Icons.picture_as_pdf_rounded;
      case 'doc':
      case 'docx':
        return Icons.description_rounded;
      case 'xls':
      case 'xlsx':
        return Icons.table_chart_rounded;
      case 'ppt':
      case 'pptx':
        return Icons.slideshow_rounded;
      case 'jpg':
      case 'jpeg':
      case 'png':
      case 'gif':
        return Icons.image_rounded;
      case 'zip':
      case 'rar':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  Future<void> _downloadAndOpenFile(BuildContext context, CustomHomeworkFile file) async {
    final provider = context.read<CustomHomeworkProvider>();
    final l10n = AppLocalizations.of(context)!;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${l10n.loading}...')),
    );

    final downloadedFile = await provider.downloadFile(
      fileId: file.id,
      fileName: file.fileName,
    );

    if (downloadedFile != null) {
      await OpenFilex.open(downloadedFile.path);
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(l10n.error)),
        );
      }
    }
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
        title: Text(
          l10n.deleteHomeworkQuestion,
          style: GoogleFonts.inter(fontWeight: FontWeight.w600),
        ),
        content: Text(
          l10n.deleteHomeworkWarning,
          style: GoogleFonts.inter(
            color: colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await _deleteHomework(context, l10n);
            },
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
            ),
            child: Text(l10n.delete),
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
        SnackBar(
          content: Text(success ? l10n.homeworkDeleted : l10n.error),
        ),
      );

      if (success) {
        onDeleted?.call();
      }
    }
  }
}