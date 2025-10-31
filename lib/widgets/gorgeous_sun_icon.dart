import 'package:flutter/material.dart';
import 'dart:math' as math;

/// オシャレな光を放つ太陽アイコン
class GorgeousSunIcon extends StatelessWidget {
  final double size;
  final double glowSpread;
  final double rayLength;

  const GorgeousSunIcon({
    super.key,
    this.size = 32,
    this.glowSpread = 1.2,
    this.rayLength = 1.2,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 1.5, size * 1.5),
      painter: _SunPainter(
        coreSize: size,
        glowSpread: glowSpread,
        rayLength: rayLength,
      ),
    );
  }
}

class _SunPainter extends CustomPainter {
  final double coreSize;
  final double glowSpread;
  final double rayLength;

  _SunPainter({
    required this.coreSize,
    required this.glowSpread,
    required this.rayLength,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = coreSize / 2;

    // グラデーションで光を表現（オレンジ系）
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFB74D).withValues(alpha: 0.8), // オレンジ
          const Color(0xFFFF9800).withValues(alpha: 0.5), // オレンジ
          const Color(0xFFFF6F00).withValues(alpha: 0.2), // 濃いオレンジ
          Colors.transparent,
        ],
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(
          Rect.fromCircle(center: center, radius: radius * glowSpread * 2));

    // 外側の光輪を描画
    canvas.drawCircle(center, radius * glowSpread * 2, glowPaint);

    // 光線を描画（8本・オレンジ）
    final rayPaint = Paint()
      ..color = const Color(0xFFFF9800).withValues(alpha: 0.6) // オレンジ
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final angle = (i * math.pi / 4);
      final startX = center.dx + radius * 1.3 * math.cos(angle);
      final startY = center.dy + radius * 1.3 * math.sin(angle);
      final endX =
          center.dx + radius * (1.3 + rayLength * 0.8) * math.cos(angle);
      final endY =
          center.dy + radius * (1.3 + rayLength * 0.8) * math.sin(angle);
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), rayPaint);
    }

    // 太陽本体（オレンジグラデーション）
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFCC80), // 明るいオレンジ
          const Color(0xFFFFB74D), // オレンジ
          const Color(0xFFFF9800), // 濃いオレンジ
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, corePaint);

    // ハイライト
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.4);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.25, center.dy - radius * 0.25),
      radius * 0.3,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
