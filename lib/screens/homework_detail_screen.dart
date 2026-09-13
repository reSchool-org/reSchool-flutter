import 'dart:ui';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lesson_view_model.dart';
import '../services/api_service.dart';
import '../utils/app_font.dart';
import '../widgets/custom_homework_dialog.dart';
import '../widgets/homework_analysis_card.dart';
import '../widgets/homework_rich_text.dart';
import '../utils/html_content.dart';

class HomeworkDetailScreen extends StatefulWidget {
  final String subject;
  final String text;
  final String? html;
  final double? deadline;
  final List<HomeworkFile> files;
  final bool isDialog;
  final int? partId;

  /// дата урока, по ней сервер находит разбор этого задания
  final DateTime? lessonDate;

  const HomeworkDetailScreen({
    super.key,
    required this.subject,
    required this.text,
    this.html,
    this.deadline,
    required this.files,
    this.isDialog = false,
    this.partId,
    this.lessonDate,
  });

  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen>
    with SingleTickerProviderStateMixin {
  bool _isDownloading = false;
  String? _downloadingFileName;
  final ApiService _api = ApiService();

  // то, что подгружаем из lpart по требованию
  List<HomeworkFile> _lpartFiles = [];
  String? _lpartFullText;
  bool _isLoadingLPart = false;
  String? _lpartLoadError;

  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;

  List<HomeworkFile> _dedupFiles(Iterable<HomeworkFile> files) {
    // порядок сохраняем, побеждает первое вхождение
    final seen = <String, HomeworkFile>{};
    for (final f in files) {
      final url = f.url;
      final key = (url != null && url.isNotEmpty)
          ? 'url:$url'
          : 'vid:${f.variantId}|id:${f.id}|name:${f.name}';
      seen.putIfAbsent(key, () => f);
    }
    return seen.values.toList(growable: false);
  }

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

    if (widget.partId != null) {
      _loadLPartDetails();
    }
  }

  Future<void> _loadLPartDetails({bool force = false}) async {
    if (widget.partId == null) return;
    if (_isLoadingLPart) return;
    if (!force && (_lpartFiles.isNotEmpty || _lpartFullText != null)) return;

    setState(() {
      _isLoadingLPart = true;
      _lpartLoadError = null;
    });
    try {
      final detail = await _api.getLPartPupil(widget.partId!);

      final files = <HomeworkFile>[];
      for (final a in detail.attach) {
        if (a.fileId != null && a.fileName != null) {
          files.add(
            HomeworkFile(
              id: a.fileId!,
              name: a.fileName!,
              variantId: detail.varId ?? 0,
            ),
          );
        }
      }

      if (mounted) {
        setState(() {
          _lpartFiles = files;
          if (detail.taskText != null && detail.taskText!.isNotEmpty) {
            _lpartFullText = detail.taskText!;
          }
          _isLoadingLPart = false;
        });
      }
    } catch (e) {
      debugPrint("Failed to load LPart details: $e");
      if (mounted) {
        setState(() {
          _isLoadingLPart = false;
          _lpartLoadError = "Не удалось загрузить вложения";
        });
      }
    }
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
      final url =
          file.url ??
          "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/${file.variantId}/${file.id}";
      final downloadedFile = await _api.downloadXFile(url, file.name);

      if (mounted) {
        if (kIsWeb) {
          await downloadedFile.saveTo(downloadedFile.name);
          return;
        }
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
      final url =
          file.url ??
          "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/${file.variantId}/${file.id}";
      final downloadedFile = await _api.downloadXFile(url, file.name);

      if (mounted) {
        setState(() {
          _isDownloading = false;
          _downloadingFileName = null;
        });
        await SharePlus.instance.share(ShareParams(files: [downloadedFile], text: file.name));
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
        content: Text(message, style: appFont(context, fontWeight: FontWeight.w500)),
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
              // полоска для перетаскивания
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

              // имя файла
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
                            style: appFont(ctx,
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
                            style: appFont(ctx,
                              fontSize: 12,
                              color: colorScheme.onSurface.withValues(
                                alpha: 0.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),

              // действия
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
    // если lpart отдал полный текст, берём его, иначе то, что было в карточке
    final displayText = (_lpartFullText != null && _lpartFullText!.isNotEmpty)
        ? _lpartFullText!
        : widget.html ?? plainTextToHtml(widget.text);

    // файлы складываем: из карточки плюс из lpart
    final allFiles = _dedupFiles([...widget.files, ..._lpartFiles]);

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 16),

          // разбор с оценкой времени, если сервер его посчитал
          if (widget.lessonDate != null && widget.text.trim().isNotEmpty) ...[
            HomeworkAnalysisCard(
              subject: widget.subject,
              date: widget.lessonDate,
              text: widget.text,
              // задание на листочке оценить нельзя, пока кто нибудь его не сфотографирует
              onAttachMaterial: () => showDialog(
                context: context,
                builder: (_) => CustomHomeworkDialog(
                  subject: widget.subject,
                  lessonDate: widget.lessonDate!,
                ),
              ),
            ),
            const SizedBox(height: 20),
          ],

          // текст задания
          if (displayText.isNotEmpty) ...[
            Text(
              'Задание',
              style: appFont(context,
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
              child: HomeworkRichText(
                displayText,
                textStyle: appFont(context,
                  fontSize: 15,
                  height: 1.7,
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            const SizedBox(height: 28),
          ],

          // вложения
          if (_isLoadingLPart && allFiles.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                children: [
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    'Загрузка вложений...',
                    style: appFont(context,
                      fontSize: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.5),
                    ),
                  ),
                ],
              ),
            ),
          if (!_isLoadingLPart &&
              allFiles.isEmpty &&
              widget.partId != null &&
              _lpartLoadError != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 28),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _lpartLoadError!,
                      style: appFont(context,
                        fontSize: 14,
                        color: colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _loadLPartDetails(force: true),
                    child: Text(
                      'Повторить',
                      style: appFont(context,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (allFiles.isNotEmpty) ...[
            Row(
              children: [
                Text(
                  'Вложения',
                  style: appFont(context,
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
                    '${allFiles.length}',
                    style: appFont(context,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            ...allFiles.map(
              (file) => Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: _FileCard(
                  file: file,
                  icon: _getFileIcon(file.name),
                  extension: _getFileExtension(file.name),
                  onTap: () => _showFileOptions(file),
                  isDownloading:
                      _isDownloading && _downloadingFileName == file.name,
                ),
              ),
            ),
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

    // в режиме диалога Scaffold не нужен
    if (widget.isDialog) {
      return Material(
        color: colorScheme.surface,
        child: Column(
          children: [
            // шапка диалога с крестиком
            Container(
              padding: const EdgeInsets.fromLTRB(24, 16, 16, 0),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.subject,
                      style: appFont(context,
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
            // содержимое
            Expanded(child: _buildContent(colorScheme, isDark)),
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: Stack(
        children: [
          SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
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
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                    child: Text(
                      widget.subject,
                      style: appFont(context,
                        fontSize: 32,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                        height: 1.1,
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Expanded(child: _buildContent(colorScheme, isDark)),
                ],
              ),
            ),
          ),

          // затемнение на время загрузки
          if (_isDownloading)
            _LoadingOverlay(fileName: _downloadingFileName ?? ''),
        ],
      ),
    );
  }
}

// пункт действия
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
                child: Icon(icon, color: colorScheme.primary, size: 20),
              ),
              const SizedBox(width: 14),
              Text(
                label,
                style: appFont(context,
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

// карточка файла
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
                    : Icon(icon, color: colorScheme.primary, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      file.name,
                      style: appFont(context,
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
                      style: appFont(context,
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

// затемнение на время загрузки
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
                  style: appFont(context,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  fileName,
                  style: appFont(context,
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
