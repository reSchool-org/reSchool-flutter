import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../services/api_service.dart';
import 'app_card.dart';
import '../utils/app_font.dart';

class ContentImage extends StatefulWidget {
  final Uri uri;
  final String? label;
  final BoxFit fit;
  final double? height;
  const ContentImage({
    super.key,
    required this.uri,
    this.label,
    this.fit = BoxFit.contain,
    this.height,
  });

  @override
  State<ContentImage> createState() => _ContentImageState();
}

class _ContentImageState extends State<ContentImage> {
  late Future<Uint8List> _bytes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() {
    _bytes = ApiService().getContentImage(widget.uri);
  }

  @override
  void didUpdateWidget(ContentImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.uri != widget.uri) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: FutureBuilder<Uint8List>(
        future: _bytes,
        builder: (context, snapshot) {
          Widget failure() => Container(
            height: widget.height ?? 120,
            color: appCardFill(context),
            alignment: Alignment.center,
            child: IconButton(
              tooltip: '${l10n.imageLoadError}. ${l10n.retry}',
              icon: const Icon(Icons.broken_image_outlined),
              onPressed: () => setState(_load),
            ),
          );
          if (snapshot.hasError) return failure();
          if (snapshot.connectionState != ConnectionState.done ||
              !snapshot.hasData) {
            return SizedBox(
              height: widget.height ?? 120,
              child: const Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            );
          }
          return Semantics(
            button: true,
            label: widget.label ?? l10n.openImage,
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (context) => Scaffold(
                    backgroundColor: Colors.black,
                    appBar: AppBar(
                      backgroundColor: Colors.black,
                      foregroundColor: Colors.white,
                      title: Text(widget.label ?? l10n.openImage, style: appFont(context)),
                    ),
                    body: Center(
                      child: InteractiveViewer(
                        minScale: 0.5,
                        maxScale: 6,
                        child: Image.memory(
                          snapshot.data!,
                          fit: BoxFit.contain,
                          errorBuilder: (_, error, stack) => const Icon(
                            Icons.broken_image,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child: Image.memory(
                snapshot.data!,
                fit: widget.fit,
                height: widget.height,
                width: widget.height == null ? null : double.infinity,
                semanticLabel: widget.label,
                errorBuilder: (_, error, stack) => failure(),
              ),
            ),
          );
        },
      ),
    );
  }
}
