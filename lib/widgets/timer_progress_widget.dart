import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../utils/time_utils.dart';

class TimerProgressWidget extends StatefulWidget {
  final String startTime;
  final String endTime;
  final Color? color;
  final TextStyle? textStyle;
  final String label;
  final bool isBreak;

  const TimerProgressWidget({
    super.key,
    required this.startTime,
    required this.endTime,
    this.color,
    this.textStyle,
    this.label = "До конца:",
    this.isBreak = false,
  });

  @override
  State<TimerProgressWidget> createState() => _TimerProgressWidgetState();
}

class _TimerProgressWidgetState extends State<TimerProgressWidget>
    with SingleTickerProviderStateMixin {
  Timer? _timer;
  double _progress = 0.0;
  int _secondsLeft = 0;
  late AnimationController _shimmerController;

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat();
    _updateProgress();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateProgress());
  }

  @override
  void dispose() {
    _timer?.cancel();
    _shimmerController.dispose();
    super.dispose();
  }

  void _updateProgress() {
    final now = DateTime.now();
    final currentSeconds = now.hour * 3600 + now.minute * 60 + now.second;

    final startSeconds = TimeUtils.toSeconds(widget.startTime);
    final endSeconds = TimeUtils.toSeconds(widget.endTime);

    if (startSeconds == -1 || endSeconds == -1) return;

    final totalDuration = endSeconds - startSeconds;
    final elapsed = currentSeconds - startSeconds;

    double newProgress = 0.0;
    if (totalDuration > 0) {
      newProgress = (elapsed / totalDuration).clamp(0.0, 1.0);
    }

    final remaining = endSeconds - currentSeconds;

    if (mounted) {
      setState(() {
        _progress = newProgress;
        _secondsLeft = remaining > 0 ? remaining : 0;
      });
    }
  }

  String _formatTime(int seconds) {
    if (seconds <= 0) return "0:00";
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return "$mins:${secs.toString().padLeft(2, '0')}";
  }

  void _showDetailedTimer() {
    HapticFeedback.mediumImpact();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _DetailedTimerSheet(
        startTime: widget.startTime,
        endTime: widget.endTime,
        color: widget.color ?? Theme.of(context).colorScheme.primary,
        isBreak: widget.isBreak,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final baseColor = widget.color ?? theme.colorScheme.primary;

    return GestureDetector(
      onTap: _showDetailedTimer,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Text(
                    widget.label,
                    style: widget.textStyle ?? theme.textTheme.bodySmall,
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.touch_app_rounded,
                    size: 14,
                    color: (widget.textStyle?.color ?? theme.colorScheme.onSurfaceVariant)
                        .withValues(alpha: 0.5),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: baseColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _formatTime(_secondsLeft),
                  style: (widget.textStyle ?? theme.textTheme.bodySmall)?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 8,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [

                  Container(
                    decoration: BoxDecoration(
                      color: baseColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),

                  FractionallySizedBox(
                    widthFactor: _progress,
                    child: AnimatedBuilder(
                      animation: _shimmerController,
                      builder: (context, child) {
                        return Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(4),
                            gradient: LinearGradient(
                              colors: [
                                baseColor,
                                Color.lerp(baseColor, Colors.white, 0.3)!,
                                baseColor,
                              ],
                              stops: [
                                0.0,
                                _shimmerController.value,
                                1.0,
                              ],
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: baseColor.withValues(alpha: 0.4),
                                blurRadius: 6,
                                spreadRadius: 0,
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DetailedTimerSheet extends StatefulWidget {
  final String startTime;
  final String endTime;
  final Color color;
  final bool isBreak;

  const _DetailedTimerSheet({
    required this.startTime,
    required this.endTime,
    required this.color,
    required this.isBreak,
  });

  @override
  State<_DetailedTimerSheet> createState() => _DetailedTimerSheetState();
}

class _DetailedTimerSheetState extends State<_DetailedTimerSheet> {
  Timer? _timer;
  double _progress = 0.0;
  int _secondsLeft = 0;
  int _totalSeconds = 0;

  @override
  void initState() {
    super.initState();
    _updateProgress();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _updateProgress());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _updateProgress() {
    final now = DateTime.now();
    final currentSeconds = now.hour * 3600 + now.minute * 60 + now.second;

    final startSeconds = TimeUtils.toSeconds(widget.startTime);
    final endSeconds = TimeUtils.toSeconds(widget.endTime);

    if (startSeconds == -1 || endSeconds == -1) return;

    _totalSeconds = endSeconds - startSeconds;
    final elapsed = currentSeconds - startSeconds;

    double newProgress = 0.0;
    if (_totalSeconds > 0) {
      newProgress = (elapsed / _totalSeconds).clamp(0.0, 1.0);
    }

    final remaining = endSeconds - currentSeconds;

    if (mounted) {
      setState(() {
        _progress = newProgress;
        _secondsLeft = remaining > 0 ? remaining : 0;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final size = MediaQuery.of(context).size;

    final minutes = _secondsLeft ~/ 60;
    final seconds = _secondsLeft % 60;

    return Container(
      height: size.height * 0.55,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            theme.colorScheme.surface,
            Color.lerp(theme.colorScheme.surface, widget.color, 0.05)!,
          ],
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        children: [
          const SizedBox(height: 12),
          Container(
            width: 48,
            height: 4,
            decoration: BoxDecoration(
              color: theme.colorScheme.outlineVariant,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            widget.isBreak ? "Перемена" : "Урок",
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            "${TimeUtils.formatForDisplay(widget.startTime)} — ${TimeUtils.formatForDisplay(widget.endTime)}",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.outline,
            ),
          ),
          const Spacer(flex: 1),

          Flexible(
            flex: 0,
            child: SizedBox(
              width: 200,
              height: 200,
              child: Stack(
                alignment: Alignment.center,
                children: [

                  Container(
                    width: 180,
                    height: 180,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surface,
                      boxShadow: [
                        BoxShadow(
                          color: widget.color.withValues(alpha: 0.2),
                          blurRadius: 30,
                          spreadRadius: 5,
                        ),
                      ],
                    ),
                  ),

                  SizedBox(
                    width: 180,
                    height: 180,
                    child: CustomPaint(
                      painter: _CircularProgressPainter(
                        progress: _progress,
                        color: widget.color,
                        backgroundColor: widget.color.withValues(alpha: 0.1),
                        strokeWidth: 12,
                      ),
                    ),
                  ),

                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildTimeDigit(context, minutes.toString().padLeft(2, '0')),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: Text(
                              ":",
                              style: theme.textTheme.displayMedium?.copyWith(
                                fontWeight: FontWeight.w300,
                                color: widget.color,
                              ),
                            ),
                          ),
                          _buildTimeDigit(context, seconds.toString().padLeft(2, '0')),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const Spacer(flex: 1),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildStatItem(
                  context,
                  Icons.hourglass_empty_rounded,
                  "Прошло",
                  _formatDuration(_totalSeconds - _secondsLeft),
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: theme.colorScheme.outlineVariant,
                ),
                _buildStatItem(
                  context,
                  Icons.percent_rounded,
                  "Прогресс",
                  "${(_progress * 100).toInt()}%",
                ),
                Container(
                  width: 1,
                  height: 40,
                  color: theme.colorScheme.outlineVariant,
                ),
                _buildStatItem(
                  context,
                  Icons.schedule_rounded,
                  "Всего",
                  _formatDuration(_totalSeconds),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildTimeDigit(BuildContext context, String value) {
    final theme = Theme.of(context);
    return Text(
      value,
      style: theme.textTheme.displayMedium?.copyWith(
        fontWeight: FontWeight.w200,
        color: theme.colorScheme.onSurface,
        fontFeatures: const [FontFeature.tabularFigures()],
        letterSpacing: -2,
      ),
    );
  }

  Widget _buildStatItem(BuildContext context, IconData icon, String label, String value) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Icon(icon, size: 20, color: widget.color.withValues(alpha: 0.7)),
        const SizedBox(height: 4),
        Text(
          label,
          style: theme.textTheme.labelSmall?.copyWith(
            color: theme.colorScheme.outline,
          ),
        ),
        Text(
          value,
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final mins = seconds ~/ 60;
    if (mins >= 60) {
      final hours = mins ~/ 60;
      final remainingMins = mins % 60;
      return "${hours}ч ${remainingMins}м";
    }
    return "$mins мин";
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final Color backgroundColor;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.backgroundColor,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;

    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, backgroundPaint);

    final rect = Rect.fromCircle(center: center, radius: radius);
    final gradient = SweepGradient(
      startAngle: -math.pi / 2,
      endAngle: math.pi * 1.5,
      colors: [
        color.withValues(alpha: 0.5),
        color,
        color,
      ],
      stops: const [0.0, 0.5, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      progress * 2 * math.pi,
      false,
      progressPaint,
    );

    if (progress > 0 && progress < 1) {
      final endAngle = -math.pi / 2 + progress * 2 * math.pi;
      final endPoint = Offset(
        center.dx + radius * math.cos(endAngle),
        center.dy + radius * math.sin(endAngle),
      );

      final glowPaint = Paint()
        ..color = color
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

      canvas.drawCircle(endPoint, strokeWidth / 2, glowPaint);

      final dotPaint = Paint()..color = Colors.white;
      canvas.drawCircle(endPoint, strokeWidth / 3, dotPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress;
  }
}