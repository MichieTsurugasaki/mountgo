import 'package:flutter/material.dart';

/// 🌈 共通グラデーションボーダー
/// ----------------------------------------------
/// ResultPage / DetailPage / SearchPage など全画面で共通利用可能。
/// Flutter 3.27以降対応済み。
///
/// 使用例:
/// Container(
///   decoration: BoxDecoration(
///     border: GradientBoxBorder(
///       gradient: LinearGradient(colors: [Color(0xFFF29F05), Color(0xFFF20390)]),
///       width: 3,
///     ),
///     borderRadius: BorderRadius.circular(16),
///   ),
/// )
/// ----------------------------------------------
class GradientBoxBorder extends BoxBorder {
  final Gradient gradient; // 枠線のグラデーション
  final double width; // 枠の太さ

  const GradientBoxBorder({
    required this.gradient,
    this.width = 2.0,
  });

  // --- Flutter 3.27以降必須となったgetter群 ---
  @override
  BorderSide get top => BorderSide.none;

  @override
  BorderSide get bottom => BorderSide.none;

  @override
  bool get isUniform => true;

  @override
  EdgeInsetsGeometry get dimensions => EdgeInsets.all(width);

  @override
  ShapeBorder scale(double t) => GradientBoxBorder(
        gradient: gradient,
        width: width * t,
      );

  // --- 内外パス定義 ---
  @override
  Path getInnerPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect.deflate(width));
  }

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) {
    return Path()..addRect(rect);
  }

  // --- 実際の描画処理 ---
  @override
  void paint(
    Canvas canvas,
    Rect rect, {
    TextDirection? textDirection,
    BoxShape shape = BoxShape.rectangle,
    BorderRadius? borderRadius,
  }) {
    final paint = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;

    switch (shape) {
      case BoxShape.circle:
        canvas.drawCircle(rect.center, rect.shortestSide / 2, paint);
        break;
      case BoxShape.rectangle:
        if (borderRadius != null) {
          final rrect = borderRadius.toRRect(rect);
          canvas.drawRRect(rrect, paint);
        } else {
          canvas.drawRect(rect, paint);
        }
        break;
    }
  }

  Paint toPaint() {
    final paint = Paint()
      ..shader = gradient.createShader(const Rect.fromLTWH(0, 0, 200, 70))
      ..style = PaintingStyle.stroke
      ..strokeWidth = width;
    return paint;
  }
}
