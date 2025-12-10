import 'dart:io';
import 'package:flutter/material.dart';
import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';
import '../models/lesson_view_model.dart';
import '../services/api_service.dart';

class HomeworkDetailScreen extends StatefulWidget {
  final String text;
  final double? deadline;
  final List<HomeworkFile> files;

  const HomeworkDetailScreen({
    super.key,
    required this.text,
    this.deadline,
    required this.files,
  });

  @override
  State<HomeworkDetailScreen> createState() => _HomeworkDetailScreenState();
}

class _HomeworkDetailScreenState extends State<HomeworkDetailScreen> {
  bool _isDownloading = false;
  final ApiService _api = ApiService();

  Future<void> _downloadAndOpen(HomeworkFile file) async {
    if (_isDownloading) return;

    setState(() => _isDownloading = true);

    try {
      final url = "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/${file.variantId}/${file.id}";
      final downloadedFile = await _api.downloadFile(url, file.name);

      if (mounted) {
        final result = await OpenFilex.open(downloadedFile.path);
        if (result.type != ResultType.done) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Не удалось открыть файл: ${result.message}")),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка загрузки: $e")),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDownloading = false);
      }
    }
  }

  Future<void> _shareFile(HomeworkFile file) async {
    if (_isDownloading) return;
    setState(() => _isDownloading = true);

    try {
      final url = "https://app.eschool.center/ec-server/files/HOMEWORK_VARIANT/${file.variantId}/${file.id}";
      final downloadedFile = await _api.downloadFile(url, file.name);

      if (mounted) {
        setState(() => _isDownloading = false);
        await Share.shareXFiles([XFile(downloadedFile.path)], text: file.name);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDownloading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Ошибка при попытке поделиться: $e")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text("Домашнее задание"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text("Готово", style: TextStyle(fontWeight: FontWeight.bold)),
          )
        ],
      ),
      body: Stack(
        children: [
          SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.deadline != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withOpacity(0.5),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.calendar_today, color: colorScheme.error),
                        const SizedBox(width: 12),
                        Text(
                          "Выполнить до: ${DateTime.fromMillisecondsSinceEpoch(widget.deadline!.toInt()).toString().split(' ')[0]}",
                          style: theme.textTheme.titleMedium?.copyWith(
                            color: colorScheme.error,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                if (widget.text.isNotEmpty) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: theme.cardColor,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 4),
                        )
                      ],
                    ),
                    child: SelectableText(
                      widget.text,
                      style: theme.textTheme.bodyLarge?.copyWith(height: 1.5),
                    ),
                  ),
                  const SizedBox(height: 24),
                ],

                if (widget.files.isNotEmpty) ...[
                  Text(
                    "Вложения",
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  ...widget.files.map((file) => Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: theme.cardColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(10),
                            decoration: BoxDecoration(
                              color: colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(Icons.description, color: colorScheme.primary),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: InkWell(
                              onTap: () => _downloadAndOpen(file),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    file.name,
                                    style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  Text(
                                    "Нажмите, чтобы открыть",
                                    style: theme.textTheme.labelSmall?.copyWith(color: Colors.grey),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.share_outlined),
                            tooltip: "Поделиться",
                            onPressed: () => _shareFile(file),
                          ),
                          IconButton(
                            icon: Icon(Icons.download_rounded, color: colorScheme.primary),
                            tooltip: "Скачать",
                            onPressed: () => _downloadAndOpen(file),
                          ),
                        ],
                      ),
                    ),
                  )),
                ],
              ],
            ),
          ),
          if (_isDownloading)
            Container(
              color: Colors.black.withOpacity(0.3),
              child: const Center(
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(24.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text("Загрузка файла..."),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
