import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../theme/app_theme.dart';

/// تنبيه مجاني داخل التطبيق للطلبات الجديدة التي لم يرد عليها المحل خلال 5 دقائق.
/// لا يعمل في الخلفية؛ يظهر عند فتح الشاشة أو أثناء بقائها مفتوحة.
class UnansweredOrdersAlert extends StatefulWidget {
  final List<AppOrder> orders;

  const UnansweredOrdersAlert({super.key, required this.orders});

  @override
  State<UnansweredOrdersAlert> createState() => _UnansweredOrdersAlertState();
}

class _UnansweredOrdersAlertState extends State<UnansweredOrdersAlert> {
  Timer? _clock;
  final AudioPlayer _player = AudioPlayer();
  final Set<String> _alertedOrderIds = <String>{};
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
      _notifyNewlyOverdue();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _notifyNewlyOverdue());
  }

  @override
  void didUpdateWidget(covariant UnansweredOrdersAlert oldWidget) {
    super.didUpdateWidget(oldWidget);
    _notifyNewlyOverdue();
  }

  void _notifyNewlyOverdue() {
    final newlyOverdue = widget.orders.where((order) {
      if (order.status != OrderStatus.newOrder || order.hasUnavailableItems) {
        return false;
      }
      final createdAt = order.createdAt;
      return createdAt != null &&
          _now.difference(createdAt) >= const Duration(minutes: 5) &&
          !_alertedOrderIds.contains(order.id);
    }).toList();
    if (newlyOverdue.isEmpty) return;
    _alertedOrderIds.addAll(newlyOverdue.map((order) => order.id));
    _playAlert();
  }

  Future<void> _playAlert() async {
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/bell.wav'));
    } catch (e) {
      debugPrint('Unanswered order alert sound failed: $e');
    }
  }

  @override
  void dispose() {
    _clock?.cancel();
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overdue = widget.orders.where((order) {
      if (order.status != OrderStatus.newOrder || order.hasUnavailableItems) {
        return false;
      }
      final createdAt = order.createdAt;
      return createdAt != null &&
          _now.difference(createdAt) >= const Duration(minutes: 5);
    }).toList();

    if (overdue.isEmpty) return const SizedBox.shrink();

    final activities = overdue
        .map((order) => order.createdAt)
        .whereType<DateTime>()
        .toList();
    final oldestActivity = activities.reduce(
      (a, b) => a.isBefore(b) ? a : b,
    );
    final oldest = _now.difference(oldestActivity).inMinutes;
    final countLabel = overdue.length >= 100 ? '100+' : overdue.length.toString();

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDanger.withValues(alpha: 0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.notifications_active_outlined, color: kDanger),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              'تنبيه: يوجد $countLabel طلب جديد لم يتم الرد عليه منذ 5 دقائق أو أكثر.',
              style: TextStyle(
                color: kDanger,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$oldest د',
            style: TextStyle(
              color: kDanger,
              fontWeight: FontWeight.w900,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}
