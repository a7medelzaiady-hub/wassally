import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// تنبيه مجاني داخل التطبيق للطلبات الجديدة التي لم يرد عليها المحل خلال 5 دقائق.
/// لا يعمل في الخلفية؛ يظهر عند فتح الشاشة أو أثناء بقائها مفتوحة.
class UnansweredOrdersAlert extends StatefulWidget {
  final String? storeId;

  const UnansweredOrdersAlert({super.key, this.storeId});

  @override
  State<UnansweredOrdersAlert> createState() => _UnansweredOrdersAlertState();
}

class _UnansweredOrdersAlertState extends State<UnansweredOrdersAlert> {
  Timer? _clock;
  late Stream<QuerySnapshot<Map<String, dynamic>>> _stream;
  late DateTime _now;

  @override
  void initState() {
    super.initState();
    _now = DateTime.now();
    _stream = _watch();
    _clock = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() => _now = DateTime.now());
    });
  }

  Stream<QuerySnapshot<Map<String, dynamic>>> _watch() {
    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('orders')
        .where('status', isEqualTo: 'new');
    final storeId = widget.storeId;
    if (storeId != null && storeId.isNotEmpty) {
      query = query.where('storeId', isEqualTo: storeId);
    }
    return query
        .orderBy('createdAt')
        .limit(100)
        .snapshots();
  }

  @override
  void dispose() {
    _clock?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snapshot) {
        if (snapshot.hasError || !snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        final docs = snapshot.data!.docs.where((doc) {
          final createdAt = doc.data()['createdAt'];
          return createdAt is Timestamp &&
              _now.difference(createdAt.toDate()) >= const Duration(minutes: 5);
        }).toList();
        if (docs.isEmpty) return const SizedBox.shrink();
        final firstCreatedAt = docs.first.data()['createdAt'] as Timestamp;
        final oldest = _now.difference(firstCreatedAt.toDate()).inMinutes;
        final count = docs.length;
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
                  'تنبيه: يوجد $count طلب جديد لم يتم الرد عليه منذ 5 دقائق أو أكثر.',
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
      },
    );
  }
}
