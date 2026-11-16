import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';

class _OperationsReport {
  final int newOrders;
  final int preparingOrders;
  final int onTheWayOrders;
  final int deliveredToday;
  final int openDeliveryIssues;
  final int returnsAwaitingStore;
  final int returnsConfirmed;
  final int openComplaints;
  final double collectedToday;
  final double courierEarningsToday;
  final double settlementsToday;
  final double outstanding;

  const _OperationsReport({
    required this.newOrders,
    required this.preparingOrders,
    required this.onTheWayOrders,
    required this.deliveredToday,
    required this.openDeliveryIssues,
    required this.returnsAwaitingStore,
    required this.returnsConfirmed,
    required this.openComplaints,
    required this.collectedToday,
    required this.courierEarningsToday,
    required this.settlementsToday,
    required this.outstanding,
  });
}

/// ملخص تشغيلي عند الطلب؛ يستخدم تجميعات Firestore بدل تحميل قوائم الطلبات.
class AdminOperationsReportPage extends StatefulWidget {
  const AdminOperationsReportPage({super.key});

  @override
  State<AdminOperationsReportPage> createState() =>
      _AdminOperationsReportPageState();
}

class _AdminOperationsReportPageState extends State<AdminOperationsReportPage> {
  late Future<_OperationsReport> _report = _load();

  double _sum(AggregateQuerySnapshot snapshot, String field) =>
      (snapshot.getSum(field) as num?)?.toDouble() ?? 0;

  Future<_OperationsReport> _load() async {
    final db = FirebaseFirestore.instance;
    final now = DateTime.now();
    final start = Timestamp.fromDate(DateTime(now.year, now.month, now.day));
    final orders = db.collection('orders');
    final delivered = orders.where('status', isEqualTo: 'delivered');
    final todayDelivered = delivered.where(
      'deliveredAt',
      isGreaterThanOrEqualTo: start,
    );
    final settlements = db.collection('courier_settlements');

    final results = await Future.wait([
      orders.where('status', isEqualTo: 'new').count().get(),
      orders.where('status', isEqualTo: 'preparing').count().get(),
      orders.where('status', isEqualTo: 'on_the_way').count().get(),
      todayDelivered.aggregate(
        count(),
        sum('collectedAmount'),
        sum('courierEarning'),
      ).get(),
      db.collection('delivery_issues')
          .where('status', whereIn: [
            'open',
            'in_review',
            'retry',
            'return_to_store',
            'returned_to_store',
          ])
          .count()
          .get(),
      db.collection('delivery_issues')
          .where('status', isEqualTo: 'returned_to_store')
          .count()
          .get(),
      db.collection('delivery_issues')
          .where('status', isEqualTo: 'store_confirmed_return')
          .count()
          .get(),
      db.collection('complaints')
          .where('status', whereIn: ['open', 'in_progress'])
          .count()
          .get(),
      settlements.where('createdAt', isGreaterThanOrEqualTo: start)
          .aggregate(sum('amount'))
          .get(),
      delivered.aggregate(
        sum('collectedAmount'),
        sum('courierEarning'),
      ).get(),
      settlements.aggregate(sum('amount')).get(),
    ]);

    final todayMoney = results[3];
    final allMoney = results[9];
    final totalCollected = _sum(allMoney, 'collectedAmount');
    final totalEarnings = _sum(allMoney, 'courierEarning');
    final totalSettled = _sum(results[10], 'amount');

    return _OperationsReport(
      newOrders: results[0].count ?? 0,
      preparingOrders: results[1].count ?? 0,
      onTheWayOrders: results[2].count ?? 0,
      deliveredToday: todayMoney.count ?? 0,
      openDeliveryIssues: results[4].count ?? 0,
      returnsAwaitingStore: results[5].count ?? 0,
      returnsConfirmed: results[6].count ?? 0,
      openComplaints: results[7].count ?? 0,
      collectedToday: _sum(todayMoney, 'collectedAmount'),
      courierEarningsToday: _sum(todayMoney, 'courierEarning'),
      settlementsToday: _sum(results[8], 'amount'),
      outstanding: totalCollected - totalEarnings - totalSettled,
    );
  }

  void _refresh() => setState(() => _report = _load());

  Widget _metric(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kLine),
      ),
      child: Row(
        children: [
          Icon(icon, color: Brand.green, size: 24),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: kMuted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  value,
                  style: TextStyle(
                    color: Brand.ink,
                    fontWeight: FontWeight.w900,
                    fontSize: 19,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(String title, List<Widget> children) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: Brand.ink,
              fontSize: 15,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      );

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final dateLabel = '${now.day}/${now.month}/${now.year}';
    return Scaffold(
      appBar: AppBar(
        title: const Text('تقرير التشغيل'),
        actions: [
          IconButton(
            tooltip: 'تحديث التقرير',
            onPressed: _refresh,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: FutureBuilder<_OperationsReport>(
        future: _report,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final error = snapshot.error;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.error_outline, size: 38),
                    const SizedBox(height: 10),
                    const Text(
                      'تعذر تحميل التقرير. تحقق من صلاحيات الإدارة وفهارس Firestore.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '$error',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                    TextButton(
                      onPressed: _refresh,
                      child: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final r = snapshot.data!;
          final outstandingText = r.outstanding >= 0
              ? formatPrice(r.outstanding)
              : 'رصيد زائد ${formatPrice(-r.outstanding)}';
          return RefreshIndicator(
            onRefresh: () async {
              _refresh();
              await _report;
            },
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                Text(
                  'ملخص يوم $dateLabel',
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
                const SizedBox(height: 14),
                _section('حالة الطلبات الحالية', [
                  _metric('طلبات جديدة معلّقة', '${r.newOrders}', Icons.fiber_new_outlined),
                  const SizedBox(height: 8),
                  _metric('قيد التجهيز', '${r.preparingOrders}', Icons.restaurant_outlined),
                  const SizedBox(height: 8),
                  _metric('في الطريق', '${r.onTheWayOrders}', Icons.delivery_dining_outlined),
                ]),
                const SizedBox(height: 20),
                _section('نتائج اليوم', [
                  _metric('طلبات تم تسليمها', '${r.deliveredToday}', Icons.task_alt_outlined),
                  const SizedBox(height: 8),
                  _metric('النقدية المحصّلة', formatPrice(r.collectedToday), Icons.payments_outlined),
                  const SizedBox(height: 8),
                  _metric('عمولات المناديب', formatPrice(r.courierEarningsToday), Icons.account_balance_wallet_outlined),
                  const SizedBox(height: 8),
                  _metric('توريدات المناديب', formatPrice(r.settlementsToday), Icons.price_check_outlined),
                ]),
                const SizedBox(height: 20),
                _section('المتابعة والمطابقة', [
                  _metric('بلاغات تسليم تحتاج متابعة', '${r.openDeliveryIssues}', Icons.report_problem_outlined),
                  const SizedBox(height: 8),
                  _metric('شكاوى لم تُغلق', '${r.openComplaints}', Icons.support_agent_outlined),
                  const SizedBox(height: 8),
                  _metric('صافي النقدية المطلوب توريده إجمالًا', outstandingText, Icons.account_balance_outlined),
                ]),
                const SizedBox(height: 14),
                Text(
                  'الأرقام المالية محسوبة من الطلبات المسلّمة وسجلات التوريد. '
                  'التقرير لا يغيّر الطلبات أو الأرصدة، ولا يعرض بيانات تواصل العملاء. '
                  'لا يحسب التأخير آليًا لعدم اعتماد مهلة تشغيلية (SLA) حتى الآن.',
                  style: TextStyle(color: kMuted, fontSize: 11.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
