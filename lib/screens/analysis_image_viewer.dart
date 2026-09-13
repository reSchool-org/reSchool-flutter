import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../models/homework_analysis.dart';
import '../services/analysis_service.dart';
import '../utils/app_font.dart';

/// вырезка задания во весь экран: зум, листание, отправка
class AnalysisImageViewer extends StatefulWidget {
  final List<AnalysisImage> images;
  final int initialIndex;

  const AnalysisImageViewer({
    super.key,
    required this.images,
    this.initialIndex = 0,
  });

  @override
  State<AnalysisImageViewer> createState() => _AnalysisImageViewerState();
}

class _AnalysisImageViewerState extends State<AnalysisImageViewer> {
  final AnalysisService _service = AnalysisService();
  late final PageController _pages =
      PageController(initialPage: widget.initialIndex);

  late int _index = widget.initialIndex;
  bool _sharing = false;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  AnalysisImage get _current => widget.images[_index];

  Future<void> _share() async {
    if (_sharing) return;
    HapticFeedback.lightImpact();
    setState(() => _sharing = true);
    try {
      final bytes = await _service.loadImage(_current.url);
      final directory = await getTemporaryDirectory();
      final name = _current.title.replaceAll(RegExp(r'[^0-9A-Za-zА-Яа-я]+'), '_');
      final file = File('${directory.path}/$name.png');
      await file.writeAsBytes(bytes);
      if (mounted) {
        await SharePlus.instance.share(ShareParams(files: [XFile(file.path)], text: _current.title));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Не удалось отправить',
                style: appFont(context, fontWeight: FontWeight.w500)),
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            margin: const EdgeInsets.all(16),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final image = _current;

    return Scaffold(
      backgroundColor: const Color(0xFF101012),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
              child: Row(
                children: [
                  _RoundButton(
                    icon: Icons.close_rounded,
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.pop(context);
                    },
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          image.title,
                          style: appFont(context,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: Colors.white,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (image.printedPage != null)
                          Text(
                            'Страница ${image.printedPage}',
                            style: appFont(context,
                              fontSize: 12,
                              color: Colors.white.withValues(alpha: 0.5),
                            ),
                          ),
                      ],
                    ),
                  ),
                  _RoundButton(
                    icon: Icons.ios_share_rounded,
                    busy: _sharing,
                    onTap: _share,
                  ),
                ],
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _pages,
                itemCount: widget.images.length,
                onPageChanged: (value) {
                  HapticFeedback.selectionClick();
                  setState(() => _index = value);
                },
                itemBuilder: (context, index) => _ZoomableImage(
                  image: widget.images[index],
                  service: _service,
                ),
              ),
            ),
            if (widget.images.length > 1)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: List.generate(widget.images.length, (index) {
                    final active = index == _index;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 220),
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      width: active ? 18 : 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: Colors.white
                            .withValues(alpha: active ? 0.9 : 0.25),
                        borderRadius: BorderRadius.circular(3),
                      ),
                    );
                  }),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomableImage extends StatefulWidget {
  final AnalysisImage image;
  final AnalysisService service;

  const _ZoomableImage({required this.image, required this.service});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
  final TransformationController _transform = TransformationController();
  Uint8List? _bytes;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _transform.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final bytes = await widget.service.loadImage(widget.image.url);
      if (mounted) setState(() => _bytes = bytes);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  void _toggleZoom() {
    // двойной тап переключает между вписанным и увеличенным вдвое
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.2;
    _transform.value =
        zoomed ? Matrix4.identity() : (Matrix4.identity()..scaleByDouble(2.2, 2.2, 2.2, 1));
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return Center(
        child: Text(
          'Не удалось загрузить',
          style: appFont(context, color: Colors.white.withValues(alpha: 0.5)),
        ),
      );
    }
    if (_bytes == null) {
      return const Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white24),
        ),
      );
    }

    return GestureDetector(
      onDoubleTap: _toggleZoom,
      child: InteractiveViewer(
        transformationController: _transform,
        minScale: 1,
        maxScale: 6,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              // белый фон под сканом, иначе на тёмной теме он висит в пустоте
              child: Container(
                color: Colors.white,
                child: Image.memory(
                  _bytes!,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.high,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final bool busy;

  const _RoundButton({
    required this.icon,
    required this.onTap,
    this.busy = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: busy ? null : onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white54),
                )
              : Icon(icon, color: Colors.white, size: 20),
        ),
      ),
    );
  }
}
