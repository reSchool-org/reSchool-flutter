import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/homework_analysis.dart';
import '../screens/analysis_image_viewer.dart';
import '../services/analysis_service.dart';
import '../utils/app_font.dart';

/// сводка урока: всё, что задали, одной карточкой
/// появляется, только когда в слоте больше одной записи: учитель плюс
/// одноклассник или двое одноклассников. на единственной записи её нет
class HomeworkSummaryCard extends StatefulWidget {
  final String subject;
  final DateTime date;

  /// готовая сводка, если она уже на руках, в сеть не идём
  final HomeworkSummary? initialSummary;

  const HomeworkSummaryCard({
    super.key,
    required this.subject,
    required this.date,
    this.initialSummary,
  });

  @override
  State<HomeworkSummaryCard> createState() => _HomeworkSummaryCardState();
}

class _HomeworkSummaryCardState extends State<HomeworkSummaryCard>
    with SingleTickerProviderStateMixin {
  final AnalysisService _service = AnalysisService();

  HomeworkSummary? _summary;
  bool _loading = true;

  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _fade =
      CurvedAnimation(parent: _controller, curve: Curves.easeOut);

  @override
  void initState() {
    super.initState();
    final ready = widget.initialSummary;
    if (ready != null) {
      _summary = ready;
      _loading = false;
      _controller.forward();
      return;
    }
    _load();
  }

  @override
  void didUpdateWidget(covariant HomeworkSummaryCard old) {
    super.didUpdateWidget(old);
    // сводка живёт на слоте, сменился урок или дата, значит она другая
    if (old.subject != widget.subject || old.date != widget.date) {
      _load();
    }
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
      final result = await _service.getSummary(
        subject: widget.subject,
        date: widget.date,
      );
      if (!mounted) return;
      setState(() {
        _summary = result;
        _loading = false;
      });
      if (result != null) _controller.forward();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final summary = _summary;
    if (_loading || summary == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;

    return FadeTransition(
      opacity: _fade,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.primary.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(18),
          border:
              Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(summary: summary, colorScheme: colorScheme),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
              child: Text(
                summary.text,
                style: appFont(context,
                  fontSize: 14,
                  height: 1.55,
                  color: colorScheme.onSurface.withValues(alpha: 0.85),
                ),
              ),
            ),
            if (summary.highlights.isNotEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 14),
                child: _Highlights(
                  items: summary.highlights,
                  colorScheme: colorScheme,
                ),
              ),
            if (summary.images.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _Gallery(
                  images: summary.images,
                  service: _service,
                  colorScheme: colorScheme,
                ),
              ),
            _Authors(authors: summary.authors, colorScheme: colorScheme),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final HomeworkSummary summary;
  final ColorScheme colorScheme;

  const _Header({required this.summary, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.summarize_rounded,
                size: 18, color: colorScheme.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Сводка',
                  style: appFont(context,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  _subtitle(summary),
                  style: appFont(context,
                    fontSize: 11.5,
                    color: colorScheme.onSurface.withValues(alpha: 0.5),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (summary.totalMinutes != null) ...[
            const SizedBox(width: 8),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.11),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                summary.formattedTime,
                style: appFont(context,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.primary,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _subtitle(HomeworkSummary summary) {
    final parts = <String>['${summary.partCount} ${_records(summary.partCount)}'];
    if (summary.images.isNotEmpty) {
      parts.add('${summary.images.length} ${_pictures(summary.images.length)}');
    }
    return parts.join(' · ');
  }

  static String _records(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'запись';
    if ([2, 3, 4].contains(count % 10) && !(count % 100 >= 12 && count % 100 <= 14)) {
      return 'записи';
    }
    return 'записей';
  }

  static String _pictures(int count) {
    if (count % 10 == 1 && count % 100 != 11) return 'картинка';
    if ([2, 3, 4].contains(count % 10) && !(count % 100 >= 12 && count % 100 <= 14)) {
      return 'картинки';
    }
    return 'картинок';
  }
}

/// что одноклассники добавили сверх учительского
class _Highlights extends StatelessWidget {
  final List<String> items;
  final ColorScheme colorScheme;

  const _Highlights({required this.items, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final item in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(top: 6),
                  width: 4,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item,
                    style: appFont(context,
                      fontSize: 12.5,
                      height: 1.45,
                      color: colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

class _Gallery extends StatelessWidget {
  final List<SummaryImage> images;
  final AnalysisService service;
  final ColorScheme colorScheme;

  const _Gallery({
    required this.images,
    required this.service,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 118,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: images.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) => _Thumb(
          image: images[index],
          service: service,
          colorScheme: colorScheme,
          onTap: () {
            HapticFeedback.lightImpact();
            Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => AnalysisImageViewer(
                images: [
                  for (var i = 0; i < images.length; i++)
                    images[i].toAnalysisImage(i),
                ],
                initialIndex: index,
              ),
            ));
          },
        ),
      ),
    );
  }
}

class _Thumb extends StatefulWidget {
  final SummaryImage image;
  final AnalysisService service;
  final ColorScheme colorScheme;
  final VoidCallback onTap;

  const _Thumb({
    required this.image,
    required this.service,
    required this.colorScheme,
    required this.onTap,
  });

  @override
  State<_Thumb> createState() => _ThumbState();
}

class _ThumbState extends State<_Thumb> {
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
    final image = widget.image;

    return GestureDetector(
      onTap: _bytes == null ? null : widget.onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Stack(
            children: [
              Container(
                width: 150,
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
                    ? Image.memory(
                        _bytes!,
                        fit: BoxFit.cover,
                        alignment: Alignment.topCenter,
                        filterQuality: FilterQuality.medium,
                      )
                    : Center(
                        child: _failed
                            ? Icon(Icons.broken_image_rounded,
                                size: 18,
                                color: colorScheme.onSurface
                                    .withValues(alpha: 0.25))
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
              // фото от человека и вырезку из книги надо различать с одного взгляда
              if (image.isAttachment)
                Positioned(
                  left: 6,
                  top: 6,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: const Icon(Icons.photo_camera_rounded,
                        size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 5),
          SizedBox(
            width: 150,
            child: Text(
              image.printedPage == null
                  ? image.title
                  : '${image.title} · с. ${image.printedPage}',
              style: appFont(context,
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: colorScheme.onSurface.withValues(alpha: 0.5),
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

class _Authors extends StatelessWidget {
  final List<String> authors;
  final ColorScheme colorScheme;

  const _Authors({required this.authors, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    if (authors.isEmpty) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 11, 16, 12),
      decoration: BoxDecoration(
        color: colorScheme.primary.withValues(alpha: 0.04),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(17)),
        border: Border(
          top: BorderSide(color: colorScheme.primary.withValues(alpha: 0.1)),
        ),
      ),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text(
            'Собрано из записей:',
            style: appFont(context,
              fontSize: 11.5,
              color: colorScheme.onSurface.withValues(alpha: 0.45),
            ),
          ),
          for (final author in authors)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: colorScheme.primary.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                author,
                style: appFont(context,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.primary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
