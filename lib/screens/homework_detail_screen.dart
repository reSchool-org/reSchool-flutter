import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lesson_view_model.dart';
import '../services/api_service.dart';

class HomeworkDetailScreen extends StatefulWidget {
  final String subject;
  final String text;
  final double? deadline;
  final List<HomeworkFile> files;
  final bool isDialog;

  const HomeworkDetailScreen({
    super.key,
    required this.subject,
    required this.text,
    this.deadline,
    required this.files,
    this.isDialog = false,
  });

  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  String? _downloadingFileName;
  final ApiService _api = ApiService();

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 400),
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

  Future<void> _downloadAndOpen(HomeworkFile file) async {
    if (_isDownloading) return;

    HapticFeedback.selectionClick();
    setState(() {
      _isDownloading = true;
      _downloadingFileName = file.name;
    });

    try {
      final url = "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/${file.variantId}/${file.id}";
      final downloadedFile = await _api.downloadFile(url, file.name);

      if (mounted) {
        final result = await OpenFilex.open(downloadedFile.path);
        if (result.type != ResultType.done) {
          _showError("Не удалось открыть файл");
        }
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        _showError("Ошибка загрузки файла");
      }
    } finally {
      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingFileName = null;
        });
      }
    }
  }

  Future<void> _shareFile(HomeworkFile file) async {
    if (_isDownloading) return;
    HapticFeedback.lightImpact();
    setState(() {
      _isDownloading = true;
      _downloadingFileName = file.name;
    });

    try {
      final url = "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/${file.variantId}/${file.id}";
      final downloadedFile = await _api.downloadFile(url, file.name);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingFileName = null;
        });
        await Share.shareXFiles([XFile(downloadedFile.path)], text: file.name);
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _isDownloading = false;
          _downloadingFileName = null;
        });
        _showError("Ошибка при отправке файла");
      }
    }
  }

  void _showError(String message) {
    final colorScheme = Theme.of(context).colorScheme;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          message,
          style: GoogleFonts.inter(fontWeight: FontWeight.w500),
        ),
        backgroundColor: colorScheme.error,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  void _showFileOptions(HomeworkFile file) {
    HapticFeedback.selectionClick();
    final colorScheme = Theme.of(context).colorScheme;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          padding: const EdgeInsets.only(bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [

              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.onSurface.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getFileIcon(file.name),
                        color: colorScheme.primary,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            file.name,
                            style: GoogleFonts.inter(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            _getFileExtension(file.name).toUpperCase(),
                            style: GoogleFonts.inter(
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(alpha: 0.5),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              _ActionTile(
                icon: Icons.open_in_new_rounded,
                label: 'Открыть',
                onTap: () {
                  Navigator.pop(ctx);
                  _downloadAndOpen(file);
                },
              ),
              _ActionTile(
                icon: Icons.share_rounded,
                label: 'Поделиться',
                onTap: () {
                  Navigator.pop(ctx);
                  _shareFile(file);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getFileIcon(String fileName) {
    final ext = _getFileExtension(fileName).toLowerCase();
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
      case 'mp3':
      case 'wav':
        return Icons.audio_file_rounded;
      case 'mp4':
      case 'mov':
      case 'avi':
        return Icons.video_file_rounded;
      case 'zip':
      case 'rar':
      case '7z':
        return Icons.folder_zip_rounded;
      default:
        return Icons.insert_drive_file_rounded;
    }
  }

  String _getFileExtension(String fileName) {
    final parts = fileName.split('.');
    return parts.length > 1 ? parts.last : '';
  }

  Widget _buildContent(ColorScheme colorScheme, bool isDark) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          if (widget.text.isNotEmpty) ...[
            Text(
              'Задание',
              style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: isDark
                    ? colorScheme.onSurface.withValues(alpha: 0.03)
                    : colorScheme.onSurface.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: colorScheme.onSurface.withValues(alpha: 0.08),
                ),
              ),
              child: SelectableText(
                widget.text,
                style: GoogleFonts.inter(
                  fontSize: 15,
                  height: 1.7,
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],

          if (widget.files.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Вложения',
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(width: 10),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    '${widget.files.length}',
                    style: GoogleFonts.inter(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...widget.files.map((file) => Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _FileCard(
                file: file,
                icon: _getFileIcon(file.name),
                extension: _getFileExtension(file.name),
                onTap: () => _showFileOptions(file),
                isDownloading: _isDownloading && _downloadingFileName == file.name,
              ),
            )),
          ],

          const SizedBox(height: 40),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (widget.isDialog) {
      return Material(
        color: colorScheme.surface,
        child: Column(
          children: [

            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.subject,
                      style: GoogleFonts.outfit(
                        fontSize: 22,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Material(
                    color: isDark
                        ? colorScheme.onSurface.withValues(alpha: 0.05)
                        : colorScheme.onSurface.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(
                          Icons.close_rounded,
                          color: colorScheme.onSurface,
                          size: 22,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: _buildContent(colorScheme, isDark),
            ),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          CustomScrollView(
            slivers: [

              SliverAppBar(
                backgroundColor: Colors.transparent,
                elevation: 0,
                floating: true,
                leading: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Material(
                    color: isDark
                        ? colorScheme.onSurface.withValues(alpha: 0.05)
                        : colorScheme.onSurface.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    child: InkWell(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.circular(12),
                      child: Icon(
                        Icons.close_rounded,
                        color: colorScheme.onSurface,
                      ),
                    ),
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: FadeTransition(
                  opacity: _fadeAnimation,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [

                        Text(
                          widget.subject,
                          style: GoogleFonts.outfit(
                            fontSize: 32,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurface,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 20),

                        if (widget.text.isNotEmpty) ...[
                          Text(
                            'Задание',
                            style: GoogleFonts.outfit(
                              fontSize: 20,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: isDark
                                  ? colorScheme.onSurface.withValues(alpha: 0.03)
                                  : colorScheme.onSurface.withValues(alpha: 0.02),
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: colorScheme.onSurface.withValues(alpha: 0.08),
                              ),
                            ),
                            child: SelectableText(
                              widget.text,
                              style: GoogleFonts.inter(
                                fontSize: 15,
                                height: 1.7,
                                color: colorScheme.onSurface.withValues(alpha: 0.85),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                        ],

                        if (widget.files.isNotEmpty) ...[
                          Row(
                            children: [
                              Text(
                                'Вложения',
                                style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  '${widget.files.length}',
                                  style: GoogleFonts.inter(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          ...widget.files.map((file) => Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: _FileCard(
                              file: file,
                              icon: _getFileIcon(file.name),
                              extension: _getFileExtension(file.name),
                              onTap: () => _showFileOptions(file),
                              isDownloading: _isDownloading && _downloadingFileName == file.name,
                            ),
                          )),
                        ],

                        const SizedBox(height: 40),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),

          if (_isDownloading)
            _LoadingOverlay(fileName: _downloadingFileName ?? ''),
        ],
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () {
          HapticFeedback.selectionClick();
          onTap();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  icon,
                  color: colorScheme.primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: GoogleFonts.inter(
                  fontSize: 16,
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
}

class _FileCard extends StatelessWidget {
  final HomeworkFile file;
  final IconData icon;
  final String extension;
  final VoidCallback onTap;
  final bool isDownloading;

  const _FileCard({
    required this.file,
    required this.icon,
    required this.extension,
    required this.onTap,
    required this.isDownloading,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Material(
      color: isDark
          ? colorScheme.onSurface.withValues(alpha: 0.03)
          : colorScheme.surface,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.onSurface.withValues(alpha: 0.08),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: isDownloading
                    ? Padding(
                        padding: const EdgeInsets.all(14),
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: colorScheme.primary,
                        ),
                      )
                    : Icon(
                        icon,
                        color: colorScheme.primary,
                        size: 24,
                      ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: GoogleFonts.inter(
                        fontSize: 15,
                        fontWeight: FontWeight.w500,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      extension.toUpperCase(),
                      style: GoogleFonts.inter(
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.more_vert_rounded,
                color: colorScheme.onSurface.withValues(alpha: 0.3),
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LoadingOverlay extends StatelessWidget {
  final String fileName;

  const _LoadingOverlay({required this.fileName});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Container(
      color: Colors.black.withValues(alpha: 0.5),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
        child: Center(
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 40),
            padding: const EdgeInsets.all(28),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              borderRadius: BorderRadius.circular(20),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.1),
                  blurRadius: 20,
                ),
              ],
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 48,
                  height: 48,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: colorScheme.primary,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  'Загрузка файла',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fileName,
                  style: GoogleFonts.inter(
                    fontSize: 13,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}