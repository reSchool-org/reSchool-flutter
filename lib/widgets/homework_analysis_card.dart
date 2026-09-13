import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/homework_analysis.dart';
import '../screens/analysis_image_viewer.dart';
import '../services/analysis_service.dart';
import '../utils/app_font.dart';

/// карточка с разбором домашнего задания
/// сама тянет разбор с сервера и сама перепроверяет, пока он считается:
/// уведомление приходит уже готовым, а вот открытый экран мог опередить воркер
class HomeworkAnalysisCard extends StatefulWidget {
  final int? analysisId;
  final String? subject;
  final DateTime? date;
  final String? text;

  /// в карточке своего домашнего задания места меньше, показываем сжатую версию
  final bool compact;

  /// автору задания объясняем, почему его не отправили классу
  final bool showRejection;

  /// зовём приложить фото листочка, когда оценивать нечего
  final VoidCallback? onAttachMaterial;

  /// готовый разбор: если он уже на руках, в сеть не идём
  final HomeworkAnalysis? initialAnalysis;

  const HomeworkAnalysisCard({
    super.key,
    this.analysisId,
    this.subject,
    this.date,
    this.text,
    this.compact = false,
    this.showRejection = false,
    this.onAttachMaterial,
    this.initialAnalysis,
  });

  @override
  State<HomeworkAnalysisCard> createState() => _HomeworkAnalysisCardState();
}

class _HomeworkAnalysisCardState extends State<HomeworkAnalysisCard>
    with SingleTickerProviderStateMixin {
  final AnalysisService _service = AnalysisService();

  HomeworkAnalysis? _analysis;
  bool _loading = true;
  bool _expanded = false;

  // пока разбор считается, переспрашиваем, но недолго и всё реже
  int _polls = 0;
  static const _maxPolls = 12;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    final ready = widget.initialAnalysis;
    if (ready != null) {
      _analysis = ready;
      _loading = false;
      _controller.forward();
      return;
    }
    _load();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      if (!await _service.isAvailable()) {
        if (mounted) setState(() => _loading = false);
        return;
      }
      final result = await _service.getAnalysis(
        analysisId: widget.analysisId,
        subject: widget.subject,
        date: widget.date,
        text: widget.text,
      );
      if (!mounted) return;
      setState(() {
        _analysis = result;
        _loading = false;
      });
      if (result.status != AnalysisStatus.none) _controller.forward();
      _scheduleRetry(result);
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _scheduleRetry(HomeworkAnalysis result) {
    if (!result.status.isWorking || _polls >= _maxPolls) return;
    _polls++;
    Future.delayed(Duration(seconds: 3 + _polls * 2), () {
      if (mounted) _load();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final analysis = _analysis;

    if (_loading) return const SizedBox.shrink();
    if (analysis == null || analysis.status == AnalysisStatus.none) {
      return const SizedBox.shrink();
    }
    if (analysis.status == AnalysisStatus.rejected) {
      // чужим показывать нечего, а автору объясняем, почему пуш не ушёл
      if (!widget.showRejection) return const SizedBox.shrink();
      return FadeTransition(
        opacity: _fade,
        child: _RejectedCard(
          analysis: analysis,
          colorScheme: colorScheme,
          compact: widget.compact,
        ),
      );
    }
    if (analysis.status == AnalysisStatus.failed) {
      return const SizedBox.shrink();
    }

    if (analysis.status.isWorking) {
      return FadeTransition(
        opacity: _fade,
        child: _PendingCard(compact: widget.compact),
      );
    }
    // задание живёт на листочке, которого у нас нет: зовём приложить фото
    if (analysis.needsMaterial) {
      return FadeTransition(
        opacity: _fade,
        child: _NeedsMaterialCard(
          reason: analysis.unestimableReason,
          colorScheme: colorScheme,
          compact: widget.compact,
          onAttach: widget.onAttachMaterial,
        ),
      );
    }
    if (!analysis.hasEstimate) return const SizedBox.shrink();

    return FadeTransition(
      opacity: _fade,
      child: _ResultCard(
        analysis: analysis,
        colorScheme: colorScheme,
        compact: widget.compact,
        expanded: _expanded,
        onToggle: () {
          HapticFeedback.selectionClick();
          setState(() => _expanded = !_expanded);
        },
        service: _service,
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final HomeworkAnalysis analysis;
  final ColorScheme colorScheme;
  final bool compact;
  final bool expanded;
  final VoidCallback onToggle;
  final AnalysisService service;

  const _ResultCard({
    required this.analysis,
    required this.colorScheme,
    required this.compact,
    required this.expanded,
    required this.onToggle,
    required this.service,
  });

  @override
  Widget build(BuildContext context) {
    final conflict = analysis.firstConflict;

    return Container(
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(
          color: colorScheme.primary.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Header(
            analysis: analysis,
            colorScheme: colorScheme,
            compact: compact,
            expanded: expanded,
            onToggle: analysis.items.isEmpty ? null : onToggle,
          ),
          if (analysis.images.isNotEmpty)
            Padding(
              padding: EdgeInsets.only(bottom: compact ? 12 : 14),
              child: _CropStrip(
                images: analysis.images,
                service: service,
                colorScheme: colorScheme,
                padding: compact ? 12 : 16,
              ),
            ),
          AnimatedCrossFade(
            firstChild: const SizedBox(width: double.infinity),
            secondChild: _Details(
              analysis: analysis,
              colorScheme: colorScheme,
              compact: compact,
            ),
            crossFadeState: expanded
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 260),
            sizeCurve: Curves.easeOutCubic,
          ),
          if (conflict != null)
            Padding(
              padding: EdgeInsets.fromLTRB(compact ? 12 : 16, 0, compact ? 12 : 16, 12),
              child: _ConflictBadge(text: conflict, colorScheme: colorScheme),
            ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final HomeworkAnalysis analysis;
  final ColorScheme colorScheme;
  final bool compact;
  final bool expanded;
  final VoidCallback? onToggle;

  const _Header({
    required this.analysis,
    required this.colorScheme,
    required this.compact,
    required this.expanded,
    this.onToggle,
  });

  /// вилка и самое трудное живут на второй строке: рядом с крупным временем
  /// им не хватает места на узком экране
  static String _subtitle(HomeworkAnalysis analysis, AnalysisItem? hardest) {
    final parts = <String>[];
    if (analysis.rangeMin != null && analysis.rangeMax != null) {
      parts.add('${analysis.rangeMin}-${analysis.rangeMax} мин');
    }
    if (hardest != null) parts.add('сложнее: ${hardest.label}');
    return parts.isEmpty ? 'Примерная оценка' : parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final hardest = analysis.hardestItem;
    final padding = compact ? 12.0 : 16.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(compact ? 14 : 18),
      child: InkWell(
        onTap: onToggle,
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: compact ? 34 : 40,
                height: compact ? 34 : 40,
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(compact ? 10 : 12),
                ),
                child: Icon(
                  Icons.schedule_rounded,
                  size: compact ? 18 : 21,
                  color: colorScheme.primary,
                ),
              ),
              SizedBox(width: compact ? 10 : 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      analysis.formattedTime,
                      style: appFont(context,
                        fontSize: compact ? 17 : 20,
                        fontWeight: FontWeight.w700,
                        color: colorScheme.onSurface,
                        letterSpacing: -0.3,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _subtitle(analysis, hardest),
                      style: appFont(context,
                        fontSize: compact ? 11.5 : 12.5,
                        color: colorScheme.onSurface.withValues(alpha: 0.5),
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              if (hardest != null) ...[
                const SizedBox(width: 8),
                _DifficultyBar(
                  value: hardest.difficulty,
                  colorScheme: colorScheme,
                ),
              ],
              if (onToggle != null) ...[
                const SizedBox(width: 4),
                AnimatedRotation(
                  turns: expanded ? 0.5 : 0,
                  duration: const Duration(milliseconds: 260),
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _Details extends StatelessWidget {
  final HomeworkAnalysis analysis;
  final ColorScheme colorScheme;
  final bool compact;

  const _Details({
    required this.analysis,
    required this.colorScheme,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 12.0 : 16.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(
          height: 1,
          thickness: 1,
          color: colorScheme.primary.withValues(alpha: 0.1),
          indent: padding,
          endIndent: padding,
        ),
        Padding(
          padding: EdgeInsets.fromLTRB(padding, 12, padding, 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final item in analysis.items)
                _ItemRow(
                  item: item,
                  colorScheme: colorScheme,
                  compact: compact,
                ),
            ],
          ),
        ),
        if (analysis.why != null && analysis.why!.trim().isNotEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(padding, 10, padding, 0),
            child: Text(
              analysis.why!,
              style: appFont(context,
                fontSize: 12.5,
                height: 1.5,
                color: colorScheme.onSurface.withValues(alpha: 0.55),
              ),
            ),
          ),
        SizedBox(height: padding),
      ],
    );
  }
}

class _ItemRow extends StatelessWidget {
  final AnalysisItem item;
  final ColorScheme colorScheme;
  final bool compact;

  const _ItemRow({
    required this.item,
    required this.colorScheme,
    required this.compact,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.label,
                  style: appFont(context,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.85),
                  ),
                ),
                if (item.note.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    item.note,
                    style: appFont(context,
                      fontSize: 12,
                      height: 1.4,
                      color: colorScheme.onSurface.withValues(alpha: 0.45),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${item.minutes} мин',
                style: appFont(context,
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              const SizedBox(height: 5),
              _DifficultyBar(
                value: item.difficulty,
                colorScheme: colorScheme,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// пять делений: спокойный цвет на лёгком, тревожный на трудном
class _DifficultyBar extends StatelessWidget {
  final int value;
  final ColorScheme colorScheme;

  const _DifficultyBar({required this.value, required this.colorScheme});

  Color get _color {
    if (value >= 5) return const Color(0xFFE05252);
    if (value == 4) return const Color(0xFFE08A3C);
    if (value == 3) return const Color(0xFFD9B23C);
    return const Color(0xFF4CAF7D);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final active = index < value;
        return Container(
          width: 12,
          height: 4,
          margin: EdgeInsets.only(right: index == 4 ? 0 : 3),
          decoration: BoxDecoration(
            color: active
                ? _color
                : colorScheme.onSurface.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(2),
          ),
        );
      }),
    );
  }
}

/// лента вырезок из учебника
class _CropStrip extends StatelessWidget {
  final List<AnalysisImage> images;
  final AnalysisService service;
  final ColorScheme colorScheme;
  final double padding;

  const _CropStrip({
    required this.images,
    required this.service,
    required this.colorScheme,
    required this.padding,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 116,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: EdgeInsets.symmetric(horizontal: padding),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _CropThumb(
          image: images[index],
          service: service,
          colorScheme: colorScheme,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => AnalysisImageViewer(
                  images: images,
                  initialIndex: index,
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _CropThumb extends StatefulWidget {
  final AnalysisImage image;
  final AnalysisService service;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _CropThumb({
    required this.image,
    required this.service,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  State<_CropThumb> createState() => _CropThumbState();
}

class _CropThumbState extends State<_CropThumb> {
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.service.loadImage(widget.image.url);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = widget.colorScheme;

    return GestureDetector(
      onTap: _bytes == null ? null : widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 148,
            height: 92,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: colorScheme.onSurface.withValues(alpha: 0.12),
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: _bytes != null
                // вырезка это верх задания, снизу её можно обрезать
                ? Image.memory(
                    _bytes!,
                    fit: BoxFit.cover,
                    alignment: Alignment.topCenter,
                    filterQuality: FilterQuality.medium,
                  )
                : Center(
                    child: _failed
                        ? Icon(
                            Icons.broken_image_rounded,
                            size: 18,
                            color:
                                colorScheme.onSurface.withValues(alpha: 0.25),
                          )
                        : SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: colorScheme.primary
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                  ),
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 148,
            child: Text(
              widget.image.printedPage == null
                  ? widget.image.title
                  : '${widget.image.title} · с. ${widget.image.printedPage}',
              style: appFont(context,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.45),
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictBadge extends StatelessWidget {
  final String text;
  final ColorScheme colorScheme;

  const _ConflictBadge({required this.text, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    const warning = Color(0xFFE08A3C);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: warning.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline_rounded, size: 15, color: warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: appFont(context,
                fontSize: 12,
                height: 1.4,
                color: colorScheme.onSurface.withValues(alpha: 0.75),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// задания у нас нет: учитель сослался на классную работу или листочек
class _NeedsMaterialCard extends StatelessWidget {
  final String? reason;
  final ColorScheme colorScheme;
  final bool compact;
  final VoidCallback? onAttach;

  const _NeedsMaterialCard({
    required this.reason,
    required this.colorScheme,
    required this.compact,
    this.onAttach,
  });

  @override
  Widget build(BuildContext context) {
    final padding = compact ? 12.0 : 16.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: colorScheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: compact ? 34 : 40,
            height: compact ? 34 : 40,
            decoration: BoxDecoration(
              color: colorScheme.onSurface.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(compact ? 10 : 12),
            ),
            child: Icon(
              Icons.attach_file_rounded,
              size: compact ? 17 : 20,
              color: colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Задание не из учебника',
                  style: appFont(context,
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.75),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  reason?.trim().isNotEmpty == true
                      ? reason!
                      : 'Чтобы оценить время, нужен сам материал',
                  style: appFont(context,
                    fontSize: 12,
                    height: 1.45,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                ),
                if (onAttach != null) ...[
                  const SizedBox(height: 8),
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onAttach!();
                    },
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.add_a_photo_rounded,
                            size: 14, color: colorScheme.primary),
                        const SizedBox(width: 6),
                        Text(
                          'Приложить фото',
                          style: appFont(context,
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary,
                          ),
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
    );
  }
}

/// добавленное задание не отправили классу: дубль или не похоже на задание
class _RejectedCard extends StatelessWidget {
  final HomeworkAnalysis analysis;
  final ColorScheme colorScheme;
  final bool compact;

  const _RejectedCard({
    required this.analysis,
    required this.colorScheme,
    required this.compact,
  });

  bool get _isDuplicate => analysis.rejectReason == 'duplicate';

  @override
  Widget build(BuildContext context) {
    final accent =
        _isDuplicate ? const Color(0xFF6C7BA8) : const Color(0xFFE08A3C);
    final padding = compact ? 12.0 : 16.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(compact ? 14 : 18),
        border: Border.all(color: accent.withValues(alpha: 0.2)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _isDuplicate
                ? Icons.copy_all_rounded
                : Icons.report_gmailerrorred_rounded,
            size: compact ? 17 : 19,
            color: accent,
          ),
          SizedBox(width: compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isDuplicate
                      ? 'Это уже задано'
                      : 'Класс не получил уведомление',
                  style: appFont(context,
                    fontSize: compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.8),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  analysis.rejectDetail?.trim().isNotEmpty == true
                      ? analysis.rejectDetail!
                      : (_isDuplicate
                          ? 'Такое задание на этот день уже есть, повтор не рассылали.'
                          : 'Запись не похожа на домашнее задание.'),
                  style: appFont(context,
                    fontSize: 12,
                    height: 1.45,
                    color: colorScheme.onSurface.withValues(alpha: 0.55),
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

/// разбор ещё считается, показываем скелет вместо пустоты
class _PendingCard extends StatefulWidget {
  final bool compact;

  const _PendingCard({required this.compact});

  @override
  State<_PendingCard> createState() => _PendingCardState();
}

class _PendingCardState extends State<_PendingCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final padding = widget.compact ? 12.0 : 16.0;

    return Container(
      padding: EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(widget.compact ? 14 : 18),
        border: Border.all(
          color: colorScheme.onSurface.withValues(alpha: 0.07),
        ),
      ),
      child: Row(
        children: [
          FadeTransition(
            opacity: Tween<double>(begin: 0.35, end: 1).animate(_pulse),
            child: Container(
              width: widget.compact ? 34 : 40,
              height: widget.compact ? 34 : 40,
              decoration: BoxDecoration(
                color: colorScheme.onSurface.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(widget.compact ? 10 : 12),
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: widget.compact ? 17 : 20,
                color: colorScheme.onSurface.withValues(alpha: 0.35),
              ),
            ),
          ),
          SizedBox(width: widget.compact ? 10 : 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Считаем, сколько это займёт',
                  style: appFont(context,
                    fontSize: widget.compact ? 13 : 14,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Обычно занимает полминуты',
                  style: appFont(context,
                    fontSize: 11.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.4),
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
