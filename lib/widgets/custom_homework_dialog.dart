import 'dart:io';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:path_provider/path_provider.dart';
import '../l10n/app_localizations.dart';
import '../models/custom_homework.dart';
import '../providers/custom_homework_provider.dart';

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
  final _formKey = GlobalKey<FormState>();

  List<File> _selectedFiles = [];
  List<CustomHomeworkFile> _existingFiles = [];
  List<int> _filesToDelete = [];
  bool _isLoading = false;

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
    super.dispose();
  }

  Future<void> _pickFiles() async {
    final totalFiles = _selectedFiles.length + _existingFiles.length - _filesToDelete.length;
    if (totalFiles >= maxFiles) {
      _showSnackBar(AppLocalizations.of(context)!.maxFilesLimit(maxFiles));
      return;
    }

    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && mounted) {
        final allowedExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'];

        for (final file in result.files) {
          if (file.path == null) continue;

          final ext = file.name.split('.').last.toLowerCase();
          if (!allowedExtensions.contains(ext)) {
            if (mounted) _showSnackBar('${file.name}: неподдерживаемый формат');
            continue;
          }

          final fileSize = file.size;
          if (fileSize > maxFileSizeMB * 1024 * 1024) {
            if (mounted) _showSnackBar(AppLocalizations.of(context)!.fileTooLarge);
            continue;
          }

          final currentTotal = _selectedFiles.length + _existingFiles.length - _filesToDelete.length;
          if (currentTotal >= maxFiles) break;

          setState(() {
            _selectedFiles.add(File(file.path!));
          });
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Ошибка выбора файла: $e');
      }
    }
  }

  Future<void> _pasteFromClipboard() async {
    final totalFiles = _selectedFiles.length + _existingFiles.length - _filesToDelete.length;
    if (totalFiles >= maxFiles) {
      _showSnackBar(AppLocalizations.of(context)!.maxFilesLimit(maxFiles));
      return;
    }

    try {
      final imageBytes = await Pasteboard.image;

      if (imageBytes != null && mounted) {
        if (imageBytes.length > maxFileSizeMB * 1024 * 1024) {
          _showSnackBar(AppLocalizations.of(context)!.fileTooLarge);
          return;
        }

        final tempDir = await getTemporaryDirectory();
        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final tempFile = File('${tempDir.path}/clipboard_$timestamp.png');
        await tempFile.writeAsBytes(imageBytes);

        setState(() {
          _selectedFiles.add(tempFile);
        });

        _showSnackBar('Изображение добавлено из буфера');
      } else {
        final files = await Pasteboard.files();

        if (files.isNotEmpty && mounted) {
          final allowedExtensions = ['pdf', 'doc', 'docx', 'xls', 'xlsx', 'ppt', 'pptx', 'jpg', 'jpeg', 'png', 'gif', 'txt', 'zip', 'rar'];

          for (final filePath in files) {
            final file = File(filePath);
            if (!await file.exists()) continue;

            final ext = filePath.split('.').last.toLowerCase();
            if (!allowedExtensions.contains(ext)) {
              _showSnackBar('${filePath.split('/').last}: неподдерживаемый формат');
              continue;
            }

            final fileSize = await file.length();
            if (fileSize > maxFileSizeMB * 1024 * 1024) {
              _showSnackBar(AppLocalizations.of(context)!.fileTooLarge);
              continue;
            }

            final currentTotal = _selectedFiles.length + _existingFiles.length - _filesToDelete.length;
            if (currentTotal >= maxFiles) break;

            setState(() {
              _selectedFiles.add(file);
            });
          }

          if (_selectedFiles.isNotEmpty) {
            _showSnackBar('Файл добавлен из буфера');
          }
        } else {
          if (mounted) _showSnackBar('В буфере нет изображения или файла');
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('Ошибка вставки: $e');
      }
    }
  }

  void _removeNewFile(int index) {
    setState(() {
      _selectedFiles.removeAt(index);
    });
  }

  void _removeExistingFile(int fileId) {
    setState(() {
      _filesToDelete.add(fileId);
    });
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    final l10n = AppLocalizations.of(context)!;
    final provider = context.read<CustomHomeworkProvider>();

    setState(() => _isLoading = true);

    try {
      if (widget.existingHomework != null) {
        await provider.updateHomework(
          homeworkId: widget.existingHomework!.id,
          subject: widget.subject,
          lessonDate: widget.lessonDate,
          text: _textController.text.trim(),
          deleteFileIds: _filesToDelete.isNotEmpty ? _filesToDelete : null,
          newFiles: _selectedFiles.isNotEmpty ? _selectedFiles : null,
        );
        if (mounted) {
          Navigator.of(context).pop(true);
          _showSnackBar(l10n.homeworkUpdated);
        }
      } else {
        await provider.createHomework(
          subject: widget.subject,
          lessonDate: widget.lessonDate,
          text: _textController.text.trim(),
          files: _selectedFiles.isNotEmpty ? _selectedFiles : null,
        );
        if (mounted) {
          Navigator.of(context).pop(true);
          _showSnackBar(l10n.homeworkCreated);
        }
      }
    } catch (e) {
      if (mounted) {
        _showSnackBar('${l10n.error}: $e');
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isEditing = widget.existingHomework != null;

    final activeExistingFiles = _existingFiles.where((f) => !_filesToDelete.contains(f.id)).toList();
    final totalFiles = _selectedFiles.length + activeExistingFiles.length;

    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(
        children: [
          Icon(
            isEditing ? Icons.edit_rounded : Icons.add_rounded,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              isEditing ? l10n.editCustomHomework : l10n.addCustomHomework,
              style: GoogleFonts.inter(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 400,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [

                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.book_rounded, size: 20, color: colorScheme.primary),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.subject,
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w500,
                            color: colorScheme.onSurface,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                TextFormField(
                  controller: _textController,
                  maxLines: 5,
                  decoration: InputDecoration(
                    labelText: l10n.homeworkText,
                    hintText: l10n.homeworkTextHint,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    alignLabelWithHint: true,
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return l10n.homeworkText;
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),

                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      l10n.attachFiles,
                      style: GoogleFonts.inter(
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      '$totalFiles / $maxFiles',
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),

                if (activeExistingFiles.isNotEmpty) ...[
                  ...activeExistingFiles.map((file) => _buildFileChip(
                    file.fileName,
                    file.formattedSize,
                    () => _removeExistingFile(file.id),
                    colorScheme,
                  )),
                ],

                ..._selectedFiles.asMap().entries.map((entry) {
                  final file = entry.value;
                  final fileName = file.path.split('/').last;
                  final fileSize = file.lengthSync();
                  final formattedSize = _formatFileSize(fileSize);
                  return _buildFileChip(
                    fileName,
                    formattedSize,
                    () => _removeNewFile(entry.key),
                    colorScheme,
                    isNew: true,
                  );
                }),

                if (totalFiles < maxFiles) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFiles,
                          icon: const Icon(Icons.attach_file_rounded, size: 18),
                          label: Text(l10n.attachFiles),
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      OutlinedButton.icon(
                        onPressed: _pasteFromClipboard,
                        icon: const Icon(Icons.content_paste_rounded, size: 18),
                        label: const Text('Вставить'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 8),
                Text(
                  l10n.maxFileSize(maxFileSizeMB),
                  style: GoogleFonts.inter(
                    fontSize: 11,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isLoading ? null : () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: _isLoading ? null : _submit,
          child: _isLoading
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(l10n.save),
        ),
      ],
    );
  }

  Widget _buildFileChip(
    String name,
    String size,
    VoidCallback onRemove,
    ColorScheme colorScheme, {
    bool isNew = false,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isNew
            ? colorScheme.primaryContainer.withValues(alpha: 0.3)
            : colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Icon(
            _getFileIcon(name),
            size: 16,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: GoogleFonts.inter(fontSize: 12),
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  size,
                  style: GoogleFonts.inter(
                    fontSize: 10,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, size: 16, color: colorScheme.error),
            onPressed: onRemove,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
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

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}