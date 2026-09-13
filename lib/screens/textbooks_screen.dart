import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/homework_analysis.dart';
import '../services/analysis_service.dart';
import '../widgets/app_card.dart';
import '../utils/app_font.dart';

/// учебники класса: заливка pdf и наблюдение за индексацией
class TextbooksScreen extends StatefulWidget {
  const TextbooksScreen({super.key});

  @override
  State<TextbooksScreen> createState() => _TextbooksScreenState();
}

class _TextbooksScreenState extends State<TextbooksScreen> {
  final AnalysisService _service = AnalysisService();

  List<Textbook> _textbooks = [];
  bool _loading = true;
  String? _error;

  // заливка и индексация идут долго, поэтому список сам себя обновляет
  Timer? _poll;
  double? _uploadProgress;
  String? _uploadName;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final list = await _service.listTextbooks();
      if (!mounted) return;
      setState(() {
        _textbooks = list;
        _loading = false;
        _error = null;
      });
      _syncPolling();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = _clean(e);
      });
    }
  }

  /// пока хоть одна книга индексируется, тикаем, потом останавливаемся
  void _syncPolling() {
    final busy = _textbooks.any((book) => book.isWorking);
    if (busy && _poll == null) {
      _poll = Timer.periodic(const Duration(seconds: 5), (_) => _load());
    } else if (!busy) {
      _poll?.cancel();
      _poll = null;
    }
  }

  String _clean(Object error) =>
      error.toString().replaceFirst('Exception: ', '');

  Future<void> _pickAndUpload() async {
    HapticFeedback.selectionClick();
    final picked = await FilePicker.pickFile(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );
    final path = picked?.path;
    if (path == null) return;

    final file = File(path);
    if (!mounted) return;
    setState(() {
      _uploadProgress = 0;
      _uploadName = file.uri.pathSegments.last;
    });

    try {
      await _service.uploadTextbook(
        file: file,
        onProgress: (sent, total) {
          if (mounted && total > 0) {
            setState(() => _uploadProgress = sent / total);
          }
        },
      );
      if (mounted) {
        HapticFeedback.mediumImpact();
        setState(() {
          _uploadProgress = null;
          _uploadName = null;
        });
        _load();
      }
    } catch (e) {
      if (mounted) {
        HapticFeedback.heavyImpact();
        setState(() {
          _uploadProgress = null;
          _uploadName = null;
        });
        _snack(_clean(e), isError: true);
      }
    }
  }

  Future<void> _delete(Textbook book) async {
    HapticFeedback.selectionClick();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Удалить учебник?',
          style: appFont(ctx, fontWeight: FontWeight.w600, fontSize: 18),
        ),
        content: Text(
          'В разборе домашних заданий по этому предмету больше не будут отображаться материалы из учебника.',
          style: appFont(ctx, fontSize: 14, height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Отмена', style: appFont(ctx, fontWeight: FontWeight.w500)),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            child: Text('Удалить', style: appFont(ctx, fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await _service.deleteTextbook(book.id);
      if (mounted) _load();
    } catch (e) {
      if (mounted) _snack(_clean(e), isError: true);
    }
  }

  void _snack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message, style: appFont(context, fontWeight: FontWeight.w500)),
        backgroundColor: isError ? Theme.of(context).colorScheme.error : null,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        margin: const EdgeInsets.all(16),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: Text(
          'Учебники',
          style: appFont(context, fontSize: 20, fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButton: _uploadProgress != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _pickAndUpload,
              icon: const Icon(Icons.add_rounded),
              label: Text(
                'Добавить',
                style: appFont(context, fontWeight: FontWeight.w600),
              ),
            ),
      body: RefreshIndicator(onRefresh: _load, child: _buildBody(colorScheme)),
    );
  }

  Widget _buildBody(ColorScheme colorScheme) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
      children: [
        _IntroCard(colorScheme: colorScheme),
        const SizedBox(height: 16),
        if (_uploadProgress != null) ...[
          _UploadingCard(
            name: _uploadName ?? '',
            progress: _uploadProgress!,
            colorScheme: colorScheme,
          ),
          const SizedBox(height: 12),
        ],
        if (_error != null)
          _MessageCard(
            icon: Icons.cloud_off_rounded,
            title: 'Нет связи с сервером',
            text: _error!,
            colorScheme: colorScheme,
          )
        else if (_textbooks.isEmpty && _uploadProgress == null)
          _MessageCard(
            icon: Icons.menu_book_rounded,
            title: 'Учебников пока нет',
            text:
                'Загрузите учебник в формате PDF, чтобы в разборе домашних '
                'заданий отображались материалы из него.',
            colorScheme: colorScheme,
          )
        else
          for (final book in _textbooks)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _TextbookCard(
                book: book,
                colorScheme: colorScheme,
                onDelete: () => _delete(book),
              ),
            ),
      ],
    );
  }
}

class _IntroCard extends StatelessWidget {
  final ColorScheme colorScheme;

  const _IntroCard({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.auto_awesome_rounded,
            size: 20,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Задания прямо из учебника',
                  style: appFont(context, fontSize: 14.5, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                Text(
                  'Когда учитель задаёт номера, сервер находит их в книге, '
                  'вырезает и прикидывает, сколько времени уйдёт. '
                  'Просто загрузите PDF - ИИ сам заполнит название, предмет, '
                  'класс, авторов и часть книги.',
                  style: appFont(context,
                    fontSize: 12.5,
                    height: 1.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TextbookCard extends StatelessWidget {
  final Textbook book;
  final ColorScheme colorScheme;
  final VoidCallback onDelete;

  const _TextbookCard({
    required this.book,
    required this.colorScheme,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: appCardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.menu_book_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.displayTitle,
                      style: appFont(context, fontSize: 15, fontWeight: FontWeight.w600),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      [
                        if (book.subject.isNotEmpty) book.subject,
                        if (book.grade != null) '${book.grade} класс',
                        if (book.subject.isNotEmpty) book.kindLabel,
                        if (book.part != null) 'Часть ${book.part}',
                      ].join(' · '),
                      style: appFont(context,
                        fontSize: 12,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                    if (book.authors?.isNotEmpty ?? false) ...[
                      const SizedBox(height: 3),
                      Text(
                        book.authors!,
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: appFont(context,
                          fontSize: 12,
                          color: colorScheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: onDelete,
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 20,
                  color: colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _StatusRow(book: book, colorScheme: colorScheme),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  final Textbook book;
  final ColorScheme colorScheme;

  const _StatusRow({required this.book, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    if (book.isReady) {
      return Row(
        children: [
          const Icon(
            Icons.check_circle_rounded,
            size: 15,
            color: Color(0xFF4CAF7D),
          ),
          const SizedBox(width: 6),
          Text(
            'Готов · ${book.pageCount} страниц',
            style: appFont(context,
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurface.withValues(alpha: 0.55),
            ),
          ),
        ],
      );
    }

    if (book.isFailed) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline_rounded, size: 15, color: colorScheme.error),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              book.statusDetail ?? 'Не удалось разобрать книгу',
              style: appFont(context,
                fontSize: 12,
                height: 1.4,
                color: colorScheme.error.withValues(alpha: 0.85),
              ),
            ),
          ),
        ],
      );
    }

    // индексация идёт минутами, показываем полосу и страницы
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.primary,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                book.status == 'pending'
                    ? (book.statusDetail ?? 'В очереди на разбор')
                    : 'Разбираем страницы',
                style: appFont(context,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${book.indexedPages} / ${book.pageCount}',
              style: appFont(context,
                fontSize: 11.5,
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: book.progress == 0 ? null : book.progress,
            minHeight: 4,
            backgroundColor: colorScheme.onSurface.withValues(alpha: 0.07),
          ),
        ),
      ],
    );
  }
}

class _UploadingCard extends StatelessWidget {
  final String name;
  final double progress;
  final ColorScheme colorScheme;

  const _UploadingCard({
    required this.name,
    required this.progress,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.upload_rounded, size: 18, color: colorScheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  name,
                  style: appFont(context, fontSize: 14, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                '${(progress * 100).round()}%',
                style: appFont(context,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 4,
              backgroundColor: colorScheme.onSurface.withValues(alpha: 0.07),
            ),
          ),
        ],
      ),
    );
  }
}

class _MessageCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String text;
  final ColorScheme colorScheme;

  const _MessageCard({
    required this.icon,
    required this.title,
    required this.text,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 32),
      decoration: appCardDecoration(context),
      child: Column(
        children: [
          Icon(
            icon,
            size: 32,
            color: colorScheme.onSurface.withValues(alpha: 0.25),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: appFont(context, fontSize: 15, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: appFont(context,
              fontSize: 13,
              height: 1.5,
              color: colorScheme.onSurface.withValues(alpha: 0.5),
            ),
          ),
        ],
      ),
    );
  }
}
