import 'dart:async';

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
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final overdue = widget.orders.where((order) {
      if (order.status != OrderStatus.newOrder || order.hasUnavailableItems) {
        return false;
      }
      final lastActivity = order.editedAt ?? order.createdAt;
      return lastActivity != null &&
          _now.difference(lastActivity) >= const Duration(minutes: 5);
    }).toList();

    if (overdue.isEmpty) return const SizedBox.shrink();

    final oldestActivity = overdue
        .map((order) => order.editedAt ?? order.createdAt!)
        .reduce((a, b) => a.isBefore(b) ? a : b);
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
