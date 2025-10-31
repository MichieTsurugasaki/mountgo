import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class GlassCalendar {
  static const _accent = Color(0xFFEE6FAE); // アクセント（選択色）

  /// 日帰り：今日〜7日先まで。日付1つを返す
  static Future<DateTime?> openDayTrip(BuildContext context) async {
    final now = DateTime.now();
    return showDialog<DateTime>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        DateTime selected = now;
        return _GlassDialog(
          title: "日帰りの日付を選択",
          child: CalendarDatePicker(
            initialDate: now,
            firstDate: DateTime(now.year, now.month, now.day),
            lastDate: now.add(const Duration(days: 7)),
            onDateChanged: (d) => selected = d,
          ),
          onOk: () => Navigator.pop(ctx, selected),
        );
      },
    );
  }

  /// 宿泊：1つのカレンダーで開始/終了を同じUIから選択（7日以内・二泊三日まで）
  /// 返り値：Tuple (start, end) を `List<DateTime>` [start, end] で返す
  static Future<List<DateTime>?> openStay(BuildContext context) async {
    final now = DateTime.now();
    DateTime? start;
    DateTime? end;

    return showDialog<List<DateTime>>(
      context: context,
      barrierColor: Colors.black26,
      builder: (ctx) {
        return _GlassDialog(
          title: "宿泊日程（二泊三日まで）",
          child: StatefulBuilder(builder: (ctx, setState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                CalendarDatePicker(
                  initialDate: now,
                  firstDate: DateTime(now.year, now.month, now.day),
                  lastDate: now.add(const Duration(days: 7)),
                  onDateChanged: (d) {
                    setState(() {
                      if (start == null || (start != null && end != null)) {
                        // 開始を選び直し
                        start = d;
                        end = null;
                      } else if (start != null && end == null) {
                        // 終了選択
                        if (!d.isBefore(start!)) {
                          final nights = d.difference(start!).inDays;
                          if (nights > 2) {
                            _showAlert(ctx, "二泊三日までのプランです。3泊以上は選べません。");
                            return;
                          }
                          end = d;
                        } else {
                          start = d;
                        }
                      }
                    });
                  },
                ),
                const SizedBox(height: 8),
                _RangeBadge(start: start, end: end),
              ],
            );
          }),
          onOk: () {
            if (start == null) {
              _showAlert(context, "開始日を選択してください。");
              return;
            }
            // 1泊相当として開始の翌日を自動補完
            end ??= start!.add(const Duration(days: 1));
            Navigator.pop(context, [start!, end!]);
          },
        );
      },
    );
  }

  // ---- Small helpers ----
  static void _showAlert(BuildContext ctx, String msg) {
    ScaffoldMessenger.of(ctx).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        backgroundColor: _accent,
      ),
    );
  }
}

class _GlassDialog extends StatelessWidget {
  const _GlassDialog({
    required this.child,
    required this.onOk,
    required this.title,
  });

  final Widget child;
  final String title;
  final VoidCallback onOk;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      width: 520,
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
              blurRadius: 24, color: Colors.black12, offset: Offset(0, 14)),
        ],
        border: Border.all(color: Colors.white, width: 1.2),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: Color(0xFF2B5C4F),
              )),
          const SizedBox(height: 8),
          child,
          const SizedBox(height: 6),
          Row(
            children: [
              const Spacer(),
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text("キャンセル"),
              ),
              const SizedBox(width: 6),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFEE6FAE),
                  foregroundColor: Colors.white,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: onOk,
                child: const Text("OK"),
              ),
            ],
          )
        ],
      ),
    );

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      surfaceTintColor: Colors.white,
      backgroundColor: Colors.transparent,
      child: Center(child: card),
    );
  }
}

class _RangeBadge extends StatelessWidget {
  const _RangeBadge({this.start, this.end});
  final DateTime? start;
  final DateTime? end;

  @override
  Widget build(BuildContext context) {
    final df = DateFormat('M月d日(E)', 'ja_JP');
    final text = (start == null)
        ? "開始日を選択"
        : (end == null)
            ? "${df.format(start!)} 〜 終了日を選択"
            : "${df.format(start!)} 〜 ${df.format(end!)}";
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFEEC6DD)),
      ),
      child: Text(text, style: const TextStyle(color: Color(0xFF2B2B2B))),
    );
  }
}
