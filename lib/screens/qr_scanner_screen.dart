import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../utils/app_font.dart';

/// полноэкранный сканер qr кодов
/// строку отдаёт через [Navigator.pop], при отмене вернёт пусто
class QrScannerScreen extends StatefulWidget {
  const QrScannerScreen({super.key});

  @override
  State<QrScannerScreen> createState() => _QrScannerScreenState();
}

class _QrScannerScreenState extends State<QrScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    returnImage: false,
  );

  bool _scanned = false;
  bool _torchOn = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_scanned) return;
    final value = capture.barcodes.firstOrNull?.rawValue;
    if (value == null || value.isEmpty) return;
    _scanned = true;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text('Сканировать QR-код', style: appFont(context, fontWeight: FontWeight.w600, color: Colors.white)),
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          if (!kIsWeb)
            IconButton(
              icon: Icon(
                _torchOn ? Icons.flashlight_off_rounded : Icons.flashlight_on_rounded,
                color: Colors.white,
              ),
              onPressed: () {
                _controller.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
            ),
        ],
      ),
      body: Stack(
        children: [
          // картинка с камеры
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),

          // затемнение с окошком
          _ScannerOverlay(colorScheme: colorScheme),

          // подсказка внизу
          Positioned(
            left: 0,
            right: 0,
            bottom: 48,
            child: Text(
              'Наведите камеру на QR-код из приложения reSchool',
              style: appFont(context, fontSize: 13, color: Colors.white.withValues(alpha: 0.85)),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}

class _ScannerOverlay extends StatelessWidget {
  final ColorScheme colorScheme;
  const _ScannerOverlay({required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    const cutoutSize = 260.0;
    const cornerRadius = 16.0;
    const cornerLength = 28.0;
    const cornerWidth = 4.0;
    final cornerColor = Colors.white;

    return LayoutBuilder(
      builder: (context, constraints) {
        final cx = constraints.maxWidth / 2;
        final cy = constraints.maxHeight / 2;
        final left = cx - cutoutSize / 2;
        final top = cy - cutoutSize / 2;

        return Stack(
          children: [
            // затемнение собираем из четырёх прямоугольников вокруг окошка
            Positioned.fill(
              child: CustomPaint(
                painter: _OverlayPainter(
                  cutout: Rect.fromLTWH(left, top, cutoutSize, cutoutSize),
                  radius: cornerRadius,
                ),
              ),
            ),

            // уголки рамки
            Positioned(
              left: left,
              top: top,
              child: _Corner(
                xSign: 1, ySign: 1,
                length: cornerLength, width: cornerWidth,
                radius: cornerRadius, color: cornerColor,
              ),
            ),
            Positioned(
              right: constraints.maxWidth - left - cutoutSize,
              top: top,
              child: _Corner(
                xSign: -1, ySign: 1,
                length: cornerLength, width: cornerWidth,
                radius: cornerRadius, color: cornerColor,
              ),
            ),
            Positioned(
              left: left,
              bottom: constraints.maxHeight - top - cutoutSize,
              child: _Corner(
                xSign: 1, ySign: -1,
                length: cornerLength, width: cornerWidth,
                radius: cornerRadius, color: cornerColor,
              ),
            ),
            Positioned(
              right: constraints.maxWidth - left - cutoutSize,
              bottom: constraints.maxHeight - top - cutoutSize,
              child: _Corner(
                xSign: -1, ySign: -1,
                length: cornerLength, width: cornerWidth,
                radius: cornerRadius, color: cornerColor,
              ),
            ),
          ],
        );
      },
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final Rect cutout;
  final double radius;
  _OverlayPainter({required this.cutout, required this.radius});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    final full = Rect.fromLTWH(0, 0, size.width, size.height);
    final path = Path()
      ..addRect(full)
      ..addRRect(RRect.fromRectAndRadius(cutout, Radius.circular(radius)))
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_OverlayPainter old) => old.cutout != cutout;
}

class _Corner extends StatelessWidget {
  final int xSign, ySign;
  final double length, width, radius;
  final Color color;
  const _Corner({
    required this.xSign,
    required this.ySign,
    required this.length,
    required this.width,
    required this.radius,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: length + width,
      height: length + width,
      child: CustomPaint(
        painter: _CornerPainter(
          xSign: xSign, ySign: ySign,
          length: length, strokeWidth: width,
          radius: radius, color: color,
        ),
      ),
    );
  }
}

class _CornerPainter extends CustomPainter {
  final int xSign, ySign;
  final double length, strokeWidth, radius;
  final Color color;
  _CornerPainter({
    required this.xSign, required this.ySign,
    required this.length, required this.strokeWidth,
    required this.radius, required this.color,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    final w = size.width;
    final h = size.height;

    final path = Path();
    if (xSign == 1 && ySign == 1) {
      path.moveTo(strokeWidth / 2, h - strokeWidth / 2);
      path.lineTo(strokeWidth / 2, radius);
      path.arcToPoint(Offset(radius, strokeWidth / 2), radius: Radius.circular(radius));
      path.lineTo(w - strokeWidth / 2, strokeWidth / 2);
    } else if (xSign == -1 && ySign == 1) {
      path.moveTo(strokeWidth / 2, strokeWidth / 2);
      path.lineTo(w - radius, strokeWidth / 2);
      path.arcToPoint(Offset(w - strokeWidth / 2, radius), radius: Radius.circular(radius));
      path.lineTo(w - strokeWidth / 2, h - strokeWidth / 2);
    } else if (xSign == 1 && ySign == -1) {
      path.moveTo(strokeWidth / 2, strokeWidth / 2);
      path.lineTo(strokeWidth / 2, h - radius);
      path.arcToPoint(Offset(radius, h - strokeWidth / 2), radius: Radius.circular(radius));
      path.lineTo(w - strokeWidth / 2, h - strokeWidth / 2);
    } else {
      path.moveTo(w - strokeWidth / 2, strokeWidth / 2);
      path.lineTo(w - strokeWidth / 2, h - radius);
      path.arcToPoint(Offset(w - radius, h - strokeWidth / 2), radius: Radius.circular(radius));
      path.lineTo(strokeWidth / 2, h - strokeWidth / 2);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(_CornerPainter old) => false;
}
