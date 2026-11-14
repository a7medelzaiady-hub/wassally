import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../theme/app_theme.dart';

String formatElapsed(Duration d) {
  if (d.isNegative) d = Duration.zero;
  String two(int n) => n.toString().padLeft(2, '0');
  final h = d.inHours;
  final m = d.inMinutes.remainder(60);
  final s = d.inSeconds.remainder(60);
  return h > 0 ? '$h:${two(m)}:${two(s)}' : '${two(m)}:${two(s)}';
}

/// عدّاد وقت الطلب: بيشتغل كل ثانية من [start]، ويقف عند [end] (وقت التسليم).
/// لو الطلب لسه شغّال بيتلوّن: عادي، ثم برتقالي بعد 20 دقيقة، ثم أحمر بعد 40.
class OrderTimer extends StatefulWidget {
  final DateTime start;
  final DateTime? end;
  final String label;
  const OrderTimer({super.key, required this.start, this.end, this.label = ''});

  @override
  State<OrderTimer> createState() => _OrderTimerState();
}

class _OrderTimerState extends State<OrderTimer> {
  Timer? _t;

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(covariant OrderTimer old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    _t?.cancel();
    if (widget.end == null) {
      _t = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final running = widget.end == null;
    final elapsed = (widget.end ?? DateTime.now()).difference(widget.start);
    final color = !running
        ? kMuted
        : elapsed.inMinutes >= 40
        ? kDanger
        : elapsed.inMinutes >= 20
        ? const Color(0xFFE59A00)
        : kPrimary;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            running ? Icons.timer_outlined : Icons.timer_off_outlined,
            size: 14,
            color: color,
          ),
          const SizedBox(width: 4),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text(
              formatElapsed(elapsed),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: color,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          if (widget.label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(widget.label, style: TextStyle(fontSize: 11, color: color)),
          ],
        ],
      ),
    );
  }
}

/// عدّاد الطلب الكامل (من لحظة الإرسال لحد التسليم). بيرجع null لو مفيش داعي (ملغي/قديم).
Widget? orderTotalTimer({
  required DateTime? createdAt,
  required DateTime? deliveredAt,
  required bool delivered,
  required bool cancelled,
}) {
  if (createdAt == null || cancelled) return null;
  if (delivered) {
    if (deliveredAt == null) return null;
    return OrderTimer(start: createdAt, end: deliveredAt, label: 'استغرق');
  }
  return OrderTimer(start: createdAt);
}
