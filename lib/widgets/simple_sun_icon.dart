import 'package:flutter/material.dart';
import 'dart:math' as math;

/// シンプルな太陽アイコン（影なし・小さめ）
class SimpleSunIcon extends StatelessWidget {
  final double size;

  const SimpleSunIcon({
    super.key,
    this.size = 24,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 1.3, size * 1.3),
      painter: _SimpleSunPainter(coreSize: size),
    );
  }
}

class _SimpleSunPainter extends CustomPainter {
  final double coreSize;

  _SimpleSunPainter({required this.coreSize});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = coreSize / 2;

    // 光線を描画（8本・オレンジ）
    final rayPaint = Paint()
      ..color = const Color(0xFFFF9800).withValues(alpha: 0.7)
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < 8; i++) {
      final angle = (i * math.pi / 4);
      final startX = center.dx + radius * 1.2 * math.cos(angle);
      final startY = center.dy + radius * 1.2 * math.sin(angle);
      final endX = center.dx + radius * 1.6 * math.cos(angle);
      final endY = center.dy + radius * 1.6 * math.sin(angle);
      canvas.drawLine(Offset(startX, startY), Offset(endX, endY), rayPaint);
    }

    // 太陽本体（シンプルなオレンジグラデーション）
    final corePaint = Paint()
      ..shader = RadialGradient(
        colors: [
          const Color(0xFFFFCC80),
          const Color(0xFFFFB74D),
          const Color(0xFFFF9800),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, corePaint);

    // 小さなハイライト
    final highlightPaint = Paint()..color = Colors.white.withValues(alpha: 0.5);
    canvas.drawCircle(
      Offset(center.dx - radius * 0.3, center.dy - radius * 0.3),
      radius * 0.25,
      highlightPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
