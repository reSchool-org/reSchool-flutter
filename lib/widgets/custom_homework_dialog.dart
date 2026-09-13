import 'dart:io';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_homework.dart';
import '../providers/custom_homework_provider.dart';
import '../utils/app_font.dart';

class CustomHomeworkDialog extends StatefulWidget {
  final String subject;
  final DateTime lessonDate;
  final CustomHomework? existingHomework;

  const CustomHomeworkDialog({
    super.key,
    required this.subject,
    required this.lessonDate,
    this.existingHomework,
  });

  @override
  State<CustomHomeworkDialog> createState() => _CustomHomeworkDialogState();
}

class _CustomHomeworkDialogState extends State<CustomHomeworkDialog> {
  final _textController = TextEditingController();
  final _focusNode = FocusNode();

  final List<File> _selectedFiles = [];
  List<CustomHomeworkFile> _existingFiles = [];
  final List<int> _filesToDelete = [];
  bool _isLoading = false;

  final _imagePicker = ImagePicker();

  static const int maxFiles = 3;
  static const int maxFileSizeMB = 50;

  @override
  void initState() {
    super.initState();
    if (widget.existingHomework != null) {
      _textController.text = widget.existingHomework!.text;
      _existingFiles = List.from(widget.existingHomework!.files);
    }
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<CustomHomeworkFile> get _activeExistingFiles =>
      _existingFiles.where((f) => !_filesToDelete.contains(f.id)).toList();

  int get _totalFiles => _selectedFiles.length + _activeExistingFiles.length;

  Future<void> _pickFiles() async {
    if (_totalFiles >= maxFiles) {
      _showSnackBar(AppLocalizations.of(context)!.maxFilesLimit(maxFiles));
      return;
    }
    try {
      final result = await FilePicker.pickFiles(type: FileType.any);
      if (result.isNotEmpty && mounted) {
        const allowed = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'];
        for (final file in result) {
          if (file.path == null) continue;
          final ext = file.name.split('.').last.toLowerCase();
          if (!allowed.contains(ext)) { _showSnackBar('${file.name}: неподдерживаемый формат'); continue; }
          final size = await file.length();
          if (!mounted) return;
          if (size > maxFileSizeMB * 1024 * 1024) { _showSnackBar(AppLocalizations.of(context)!.fileTooLarge); continue; }
          if (_totalFiles >= maxFiles) break;
          setState(() => _selectedFiles.add(File(file.path!)));
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Ошибка выбора файла: $e');
    }
  }

  Future<void> _pasteFromClipboard() async {
    if (_totalFiles >= maxFiles) {
      _showSnackBar(AppLocalizations.of(context)!.maxFilesLimit(maxFiles));
      return;
    }
    try {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && mounted) {
        if (imageBytes.length > maxFileSizeMB * 1024 * 1024) { _showSnackBar(AppLocalizations.of(context)!.fileTooLarge); return; }
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/clipboard_${DateTime.now().millisecondsSinceEpoch}.png');
        await tempFile.writeAsBytes(imageBytes);
        if (!mounted) return;
        setState(() => _selectedFiles.add(tempFile));
        _showSnackBar('Изображение добавлено из буфера');
      } else {
        final files = await Pasteboard.files();
        if (files.isNotEmpty && mounted) {
          const allowed = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'];
          for (final path in files) {
            final file = File(path);
            if (!await file.exists()) continue;
            final ext = path.split('.').last.toLowerCase();
            if (!allowed.contains(ext)) continue;
            if (await file.length() > maxFileSizeMB * 1024 * 1024) continue;
            if (!mounted) return;
            if (_totalFiles >= maxFiles) break;
            setState(() => _selectedFiles.add(file));
          }
        } else if (mounted) {
          _showSnackBar('В буфере нет изображения или файла');
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Ошибка вставки: $e');
    }
  }

  Future<void> _pickFromGallery() async {
    if (_totalFiles >= maxFiles) {
      _showSnackBar(AppLocalizations.of(context)!.maxFilesLimit(maxFiles));
      return;
    }
    try {
      final images = await _imagePicker.pickMultiImage(imageQuality: 90);
      if (images.isNotEmpty && mounted) {
        for (final image in images) {
          if (_totalFiles >= maxFiles) break;
          final file = File(image.path);
          final size = await file.length();
          if (!mounted) return;
          if (size > maxFileSizeMB * 1024 * 1024) {
            _showSnackBar(AppLocalizations.of(context)!.fileTooLarge);
            continue;
          }
          setState(() => _selectedFiles.add(file));
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('Ошибка выбора фото: $e');
    }
  }

  Future<void> _submit() async {
    final text = _textController.text.trim();
    if (text.isEmpty) {
      _focusNode.requestFocus();
      return;
    }

    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CustomHomeworkProvider>();
    setState(() => _isLoading = true);

    try {
      if (widget.existingHomework != null) {
        await provider.updateHomework(
          homeworkId: widget.existingHomework!.id,
          subject: widget.subject,
          lessonDate: widget.lessonDate,
          text: text,
          deleteFileIds: _filesToDelete.isNotEmpty ? _filesToDelete : null,
          newFiles: _selectedFiles.isNotEmpty ? _selectedFiles : null,
        );
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop(true);
          messenger.showSnackBar(SnackBar(content: Text(l10n.homeworkUpdated, style: appFont(context))));
        }
      } else {
        await provider.createHomework(
          subject: widget.subject,
          lessonDate: widget.lessonDate,
          text: text,
          files: _selectedFiles.isNotEmpty ? _selectedFiles : null,
        );
        if (mounted) {
          final messenger = ScaffoldMessenger.of(context);
          Navigator.of(context).pop(true);
          messenger.showSnackBar(SnackBar(content: Text(l10n.homeworkCreated, style: appFont(context))));
        }
      }
    } catch (e) {
      if (mounted) _showSnackBar('${l10n.error}: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message, style: appFont(context))));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isEditing = widget.existingHomework != null;

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 40),
      child: Container(
        constraints: const BoxConstraints(maxWidth: 440),
        decoration: BoxDecoration(
          color: isDark ? colorScheme.surfaceContainerHigh : colorScheme.surface,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.4 : 0.12),
              blurRadius: 32,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // шапка
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 12, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          isEditing ? l10n.editCustomHomework : l10n.addCustomHomework,
                          style: appFont(context,
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          widget.subject,
                          style: appFont(context,
                            fontSize: 13,
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w500,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close_rounded, color: colorScheme.onSurface.withValues(alpha: 0.4)),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 16),

            // поле ввода
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _textController,
                focusNode: _focusNode,
                maxLines: 6,
                minLines: 3,
                autofocus: true,
                style: appFont(context, fontSize: 15, height: 1.5, color: colorScheme.onSurface),
                decoration: InputDecoration(
                  hintText: l10n.homeworkTextHint,
                  hintStyle: appFont(context,
                    fontSize: 15,
                    color: colorScheme.onSurface.withValues(alpha: 0.3),
                  ),
                  filled: true,
                  fillColor: isDark
                      ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.5)
                      : colorScheme.surfaceContainerLowest,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                  ),
                  contentPadding: const EdgeInsets.all(14),
                ),
              ),
            ),

            // список файлов
            if (_activeExistingFiles.isNotEmpty || _selectedFiles.isNotEmpty) ...[
              const SizedBox(height: 10),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    ..._activeExistingFiles.map((f) => _buildFileTag(
                      name: f.fileName,
                      size: f.formattedSize,
                      onRemove: () => setState(() => _filesToDelete.add(f.id)),
                      colorScheme: colorScheme,
                    )),
                    ..._selectedFiles.asMap().entries.map((e) => _buildFileTag(
                      name: e.value.path.split('/').last,
                      size: _formatSize(e.value.lengthSync()),
                      onRemove: () => setState(() => _selectedFiles.removeAt(e.key)),
                      colorScheme: colorScheme,
                      isNew: true,
                    )),
                  ],
                ),
              ),
            ],

            // нижняя панель
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 16),
              child: Row(
                children: [
                  // кнопка вложения
                  if (_totalFiles < maxFiles) ...[
                    _BottomAction(
                      icon: Icons.attach_file_rounded,
                      onTap: _pickFiles,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 4),
                    _BottomAction(
                      icon: Icons.photo_library_rounded,
                      onTap: _pickFromGallery,
                      colorScheme: colorScheme,
                    ),
                    const SizedBox(width: 4),
                    _BottomAction(
                      icon: Icons.content_paste_rounded,
                      onTap: _pasteFromClipboard,
                      colorScheme: colorScheme,
                    ),
                  ],
                  if (_totalFiles > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 8),
                      child: Text(
                        '$_totalFiles/$maxFiles',
                        style: appFont(context,
                          fontSize: 11,
                          color: colorScheme.onSurface.withValues(alpha: 0.35),
                        ),
                      ),
                    ),
                  const Spacer(),
                  // отмена
                  TextButton(
                    onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.onSurface.withValues(alpha: 0.5),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(l10n.cancel, style: appFont(context, fontSize: 14, fontWeight: FontWeight.w500)),
                  ),
                  const SizedBox(width: 6),
                  // сохранить
                  FilledButton(
                    onPressed: _isLoading ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: _isLoading
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.onPrimary,
                            ),
                          )
                        : Text(l10n.save, style: appFont(context, fontSize: 14, fontWeight: FontWeight.w600)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFileTag({
    required String name,
    required String size,
    required VoidCallback onRemove,
    required ColorScheme colorScheme,
    bool isNew = false,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
      decoration: BoxDecoration(
        color: isNew
            ? colorScheme.primary.withValues(alpha: 0.08)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isNew
              ? colorScheme.primary.withValues(alpha: 0.2)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(_fileIcon(name), size: 13, color: colorScheme.primary),
          const SizedBox(width: 5),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 100),
            child: Text(
              name,
              style: appFont(context, fontSize: 11, fontWeight: FontWeight.w500, color: colorScheme.onSurface),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            size,
            style: appFont(context, fontSize: 10, color: colorScheme.onSurface.withValues(alpha: 0.4)),
          ),
          const SizedBox(width: 2),
          GestureDetector(
            onTap: onRemove,
            child: Icon(Icons.close_rounded, size: 14, color: colorScheme.onSurface.withValues(alpha: 0.4)),
          ),
        ],
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

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}

class _BottomAction extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _BottomAction({required this.icon, required this.onTap, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(icon, size: 18, color: colorScheme.onSurface.withValues(alpha: 0.5)),
      ),
    );
  }
}
