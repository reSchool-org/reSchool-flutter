import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../services/api_service.dart';

class AuthenticatedAvatar extends StatefulWidget {
  final int? imageId;
  final String? imgObjType;
  final int? imgObjId;
  final String fallbackText;
  final double size;
  final double borderRadius;
  final bool isGroup;

  const AuthenticatedAvatar({
    super.key,
    this.imageId,
    this.imgObjType,
    this.imgObjId,
    required this.fallbackText,
    this.size = 56,
    double? borderRadius,
    this.isGroup = false,
  }) : borderRadius =
           borderRadius ?? (size / 2);

  static Color getColorForText(String text) {
    const colors = [
      Color(0xFF6366F1),
      Color(0xFF8B5CF6),
      Color(0xFFEC4899),
      Color(0xFFF43F5E),
      Color(0xFFEF4444),
      Color(0xFFF97316),
      Color(0xFFF59E0B),
      Color(0xFF84CC16),
      Color(0xFF22C55E),
      Color(0xFF14B8A6),
      Color(0xFF06B6D4),
      Color(0xFF3B82F6),
    ];

    if (text.isEmpty) return colors[0];

    int hash = 0;
    for (int i = 0; i < text.length; i++) {
      hash = text.codeUnitAt(i) + ((hash << 5) - hash);
    }
    return colors[hash.abs() % colors.length];
  }

  @override
  State<AuthenticatedAvatar> createState() => _AuthenticatedAvatarState();
}

class _AuthenticatedAvatarState extends State<AuthenticatedAvatar> {
  static const String _baseURL = "https://app.eschool.center/ec-server";
  Uint8List? _imageData;
  bool _isLoading = true;
  bool _hasError = false;

  static final Map<String, Uint8List> _imageCache = {};

  @override
  void initState() {
    super.initState();
    _loadImage();
  }

  @override
  void didUpdateWidget(AuthenticatedAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.imageId != widget.imageId ||
        oldWidget.imgObjType != widget.imgObjType ||
        oldWidget.imgObjId != widget.imgObjId) {
      _loadImage();
    }
  }

  String? _getAvatarUrl() {
    if (ApiService().isDemo) {
      return null;
    }

    if (widget.imageId != null &&
        widget.imgObjType != null &&
        widget.imgObjId != null) {
      return "$_baseURL/files/${widget.imgObjType}/${widget.imgObjId}/${widget.imageId}?preview=true";
    }
    if (widget.imgObjType != null && widget.imgObjId != null) {
      return "$_baseURL/files/${widget.imgObjType}/${widget.imgObjId}?preview=true";
    }
    if (widget.imageId != null) {
      return "$_baseURL/files/images/${widget.imageId}?preview=true";
    }
    return null;
  }

  Future<void> _loadImage() async {
    final url = _getAvatarUrl();
    if (url == null) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    if (_imageCache.containsKey(url)) {
      setState(() {
        _imageData = _imageCache[url];
        _isLoading = false;
        _hasError = false;
      });
      return;
    }

    try {
      final headers = ApiService().authHeaders;
      headers["Accept"] = "image/*, */*";

      final response = await http.get(Uri.parse(url), headers: headers);

      if (response.statusCode == 200 && response.bodyBytes.isNotEmpty) {
        _imageCache[url] = response.bodyBytes;

        if (mounted) {
          setState(() {
            _imageData = response.bodyBytes;
            _isLoading = false;
            _hasError = false;
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _isLoading = false;
            _hasError = true;
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    final avatarColor = AuthenticatedAvatar.getColorForText(widget.fallbackText);

    return Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        color: avatarColor,
        borderRadius: BorderRadius.circular(widget.borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: _buildContent(colorScheme),
    );
  }

  Widget _buildContent(ColorScheme colorScheme) {
    if (_isLoading) {
      return Center(
        child: SizedBox(
          width: widget.size * 0.4,
          height: widget.size * 0.4,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      );
    }

    if (_imageData != null && !_hasError) {
      return Image.memory(
        _imageData!,
        fit: BoxFit.cover,
        width: widget.size,
        height: widget.size,
        errorBuilder: (context, error, stackTrace) =>
            _buildFallback(colorScheme),
      );
    }

    return _buildFallback(colorScheme);
  }

  Widget _buildFallback(ColorScheme colorScheme) {
    if (widget.isGroup) {
      return Center(
        child: Icon(
          Icons.group_rounded,
          color: Colors.white,
          size: widget.size * 0.5,
        ),
      );
    }

    final initial = widget.fallbackText.isNotEmpty
        ? widget.fallbackText[0].toUpperCase()
        : '?';

    return Center(
      child: Text(
        initial,
        style: TextStyle(
          color: Colors.white,
          fontSize: widget.size * 0.4,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}