import 'package:flutter/material.dart';

/// 剱岳のような鋭い山稜線のアイコン
class MountainRidgeIcon extends StatelessWidget {
  final double size;
  final Color color;

  const MountainRidgeIcon({
    super.key,
    this.size = 40,
    this.color = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size * 2.5, size * 1.5), // 高さを増やして1.5倍に
      painter: _MountainRidgePainter(color: color),
    );
  }
}

class _MountainRidgePainter extends CustomPainter {
  final Color color;

  _MountainRidgePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.25)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);

    final path = Path();
    final shadowPath = Path();

    // 極端に劇的な山の形状：起伏を2倍に強調
    final baseY = size.height * 0.98; // ベースラインを最下部へ
    final w = size.width;
    final h = size.height;

    // 開始点（左端）
    path.moveTo(0, baseY);
    shadowPath.moveTo(3, baseY + 3);

    // 第1峰（急峻）
    path.lineTo(w * 0.08, h * 0.25);
    path.lineTo(w * 0.10, h * 0.28);
    path.lineTo(w * 0.12, h * 0.20);
    shadowPath.lineTo(w * 0.08 + 3, h * 0.25 + 3);
    shadowPath.lineTo(w * 0.10 + 3, h * 0.28 + 3);
    shadowPath.lineTo(w * 0.12 + 3, h * 0.20 + 3);

    // 超深い谷1（極端な落差）
    path.lineTo(w * 0.18, h * 0.85);
    shadowPath.lineTo(w * 0.18 + 3, h * 0.85 + 3);

    // 第2峰（非常に高い）
    path.lineTo(w * 0.24, h * 0.12);
    path.lineTo(w * 0.26, h * 0.15);
    path.lineTo(w * 0.28, h * 0.10);
    shadowPath.lineTo(w * 0.24 + 3, h * 0.12 + 3);
    shadowPath.lineTo(w * 0.26 + 3, h * 0.15 + 3);
    shadowPath.lineTo(w * 0.28 + 3, h * 0.10 + 3);

    // 超深い谷2
    path.lineTo(w * 0.34, h * 0.82);
    shadowPath.lineTo(w * 0.34 + 3, h * 0.82 + 3);

    // 第3峰（中程度）
    path.lineTo(w * 0.40, h * 0.18);
    path.lineTo(w * 0.42, h * 0.22);
    path.lineTo(w * 0.44, h * 0.15);
    shadowPath.lineTo(w * 0.40 + 3, h * 0.18 + 3);
    shadowPath.lineTo(w * 0.42 + 3, h * 0.22 + 3);
    shadowPath.lineTo(w * 0.44 + 3, h * 0.15 + 3);

    // 超深い谷3
    path.lineTo(w * 0.48, h * 0.80);
    shadowPath.lineTo(w * 0.48 + 3, h * 0.80 + 3);

    // 主峰（圧倒的な高さ）
    path.lineTo(w * 0.52, h * 0.02); // ほぼ頂点
    path.lineTo(w * 0.54, h * 0.01); // 最高峰
    path.lineTo(w * 0.56, h * 0.02);
    path.lineTo(w * 0.58, h * 0.03);
    shadowPath.lineTo(w * 0.52 + 3, h * 0.02 + 3);
    shadowPath.lineTo(w * 0.54 + 3, h * 0.01 + 3);
    shadowPath.lineTo(w * 0.56 + 3, h * 0.02 + 3);
    shadowPath.lineTo(w * 0.58 + 3, h * 0.03 + 3);

    // 超深い谷4
    path.lineTo(w * 0.62, h * 0.78);
    shadowPath.lineTo(w * 0.62 + 3, h * 0.78 + 3);

    // 第5峰（高い）
    path.lineTo(w * 0.68, h * 0.14);
    path.lineTo(w * 0.70, h * 0.17);
    path.lineTo(w * 0.72, h * 0.12);
    shadowPath.lineTo(w * 0.68 + 3, h * 0.14 + 3);
    shadowPath.lineTo(w * 0.70 + 3, h * 0.17 + 3);
    shadowPath.lineTo(w * 0.72 + 3, h * 0.12 + 3);

    // 超深い谷5
    path.lineTo(w * 0.78, h * 0.80);
    shadowPath.lineTo(w * 0.78 + 3, h * 0.80 + 3);

    // 第6峰（中程度）
    path.lineTo(w * 0.84, h * 0.25);
    path.lineTo(w * 0.86, h * 0.30);
    path.lineTo(w * 0.88, h * 0.28);
    shadowPath.lineTo(w * 0.84 + 3, h * 0.25 + 3);
    shadowPath.lineTo(w * 0.86 + 3, h * 0.30 + 3);
    shadowPath.lineTo(w * 0.88 + 3, h * 0.28 + 3);

    // 最後の谷
    path.lineTo(w * 0.94, h * 0.75);
    shadowPath.lineTo(w * 0.94 + 3, h * 0.75 + 3);

    // 右端へ
    path.lineTo(w, h * 0.85);
    path.lineTo(w, baseY);
    shadowPath.lineTo(w + 3, h * 0.85 + 3);
    shadowPath.lineTo(w + 3, baseY + 3);

    // 底辺を閉じる
    path.close();
    shadowPath.close();

    // 影を先に描画
    canvas.drawPath(shadowPath, shadowPaint);

    // メインの山稜線を描画
    canvas.drawPath(path, paint);

    // 主峰のハイライト（劇的な雪渓）
    final highlightPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    final highlightPath = Path();
    highlightPath.moveTo(w * 0.50, h * 0.08);
    highlightPath.lineTo(w * 0.52, h * 0.02);
    highlightPath.lineTo(w * 0.54, h * 0.01);
    highlightPath.lineTo(w * 0.56, h * 0.02);
    highlightPath.lineTo(w * 0.58, h * 0.03);
    highlightPath.lineTo(w * 0.60, h * 0.12);
    highlightPath.close();
    canvas.drawPath(highlightPath, highlightPaint);

    // 稜線のエッジを非常に強調
    final edgePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final edgePath = Path();
    edgePath.moveTo(w * 0.08, h * 0.25);
    edgePath.lineTo(w * 0.12, h * 0.20);
    edgePath.lineTo(w * 0.18, h * 0.85);
    edgePath.lineTo(w * 0.24, h * 0.12);
    edgePath.lineTo(w * 0.28, h * 0.10);
    edgePath.lineTo(w * 0.34, h * 0.82);
    edgePath.lineTo(w * 0.40, h * 0.18);
    edgePath.lineTo(w * 0.44, h * 0.15);
    edgePath.lineTo(w * 0.48, h * 0.80);
    edgePath.lineTo(w * 0.52, h * 0.02);
    edgePath.lineTo(w * 0.54, h * 0.01);
    edgePath.lineTo(w * 0.58, h * 0.03);
    edgePath.lineTo(w * 0.62, h * 0.78);
    edgePath.lineTo(w * 0.68, h * 0.14);
    edgePath.lineTo(w * 0.72, h * 0.12);
    edgePath.lineTo(w * 0.78, h * 0.80);
    edgePath.lineTo(w * 0.84, h * 0.25);
    edgePath.lineTo(w * 0.88, h * 0.28);
    edgePath.lineTo(w * 0.94, h * 0.75);
    canvas.drawPath(edgePath, edgePaint);

    // 追加の光の効果（第2、第5峰にも）
    final secondaryHighlight = Paint()
      ..color = Colors.white.withValues(alpha: 0.3)
      ..style = PaintingStyle.fill;

    // 第2峰
    final highlight2 = Path();
    highlight2.moveTo(w * 0.22, h * 0.18);
    highlight2.lineTo(w * 0.24, h * 0.12);
    highlight2.lineTo(w * 0.26, h * 0.15);
    highlight2.lineTo(w * 0.27, h * 0.20);
    highlight2.close();
    canvas.drawPath(highlight2, secondaryHighlight);

    // 第5峰
    final highlight5 = Path();
    highlight5.moveTo(w * 0.66, h * 0.20);
    highlight5.lineTo(w * 0.68, h * 0.14);
    highlight5.lineTo(w * 0.70, h * 0.17);
    highlight5.lineTo(w * 0.71, h * 0.22);
    highlight5.close();
    canvas.drawPath(highlight5, secondaryHighlight);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
