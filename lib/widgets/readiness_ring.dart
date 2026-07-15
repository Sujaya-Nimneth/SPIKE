import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';

/// A sleek circular progress ring for the Spike calm score indicator.
///
/// Renders a gradient arc with an outer glow and a large centered score.
class CalmRing extends StatelessWidget {
  final int score;
  final double size;
  final double strokeWidth;
  final Color primaryColor;
  final Color secondaryColor;
  final String label;

  const CalmRing({
    super.key,
    this.score = 88,
    this.size = 240,
    this.strokeWidth = 10,
    this.primaryColor = AppColors.pastelTeal,
    this.secondaryColor = AppColors.pastelSage,
    this.label = 'CALM',
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // Outer glow
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: primaryColor.withValues(alpha: 0.15),
                  blurRadius: 40,
                  spreadRadius: 5,
                ),
              ],
            ),
          ),
          // Progress ring
          CustomPaint(
            size: Size(size, size),
            painter: _RingPainter(
              progress: score / 100,
              strokeWidth: strokeWidth,
              primaryColor: primaryColor,
              secondaryColor: secondaryColor,
              trackColor: AppColors.surfaceVariant,
            ),
          ),
          // Inner score and label
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$score',
                style: Theme.of(context).textTheme.displayLarge?.copyWith(
                      color: AppColors.textPrimary,
                      fontSize: size * 0.3,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: primaryColor.withValues(alpha: 0.9),
                      letterSpacing: 2.5,
                      fontSize: size * 0.045,
                    ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final Color primaryColor;
  final Color secondaryColor;
  final Color trackColor;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.primaryColor,
    required this.secondaryColor,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track (background ring)
    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, 0, 2 * math.pi, false, trackPaint);

    // Progress arc with gradient
    final sweepAngle = 2 * math.pi * progress;
    const startAngle = -math.pi / 2; // start from top

    final gradient = SweepGradient(
      startAngle: 0,
      endAngle: sweepAngle,
      colors: [
        secondaryColor,
        primaryColor,
        primaryColor,
      ],
      stops: const [0.0, 0.6, 1.0],
      transform: const GradientRotation(-math.pi / 2),
    );

    final progressPaint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, startAngle, sweepAngle, false, progressPaint);

    // Glow dot at the end of the arc
    final endAngle = startAngle + sweepAngle;
    final dotCenter = Offset(
      center.dx + radius * math.cos(endAngle),
      center.dy + radius * math.sin(endAngle),
    );

    // Outer glow of the dot
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: 0.4)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);
    canvas.drawCircle(dotCenter, strokeWidth * 0.8, glowPaint);

    // Solid dot
    final dotPaint = Paint()..color = primaryColor;
    canvas.drawCircle(dotCenter, strokeWidth * 0.45, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.primaryColor != primaryColor;
  }
}
