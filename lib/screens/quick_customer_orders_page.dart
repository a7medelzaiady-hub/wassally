import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_tokens.dart';
import '../utils/quick_order_status.dart';
import 'quick_order_customer_detail_page.dart';

/// قائمة الطلبات السريعة: قراءة عند الفتح أو التحديث فقط، بدون listener جديد.
class QuickCustomerOrdersPage extends StatefulWidget {
  const QuickCustomerOrdersPage({super.key});

  @override
  State<QuickCustomerOrdersPage> createState() => _QuickCustomerOrdersPageState();
}

class _QuickCustomerOrdersPageState extends State<QuickCustomerOrdersPage> {
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _orders = _load();

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) throw StateError('سجل دخولك أولًا');
    final result = await FirebaseFirestore.instance
        .collection('quick_orders')
        .where('userId', isEqualTo: uid)
        .limit(50)
        .get();
    final docs = result.docs.toList();
    docs.sort((a, b) {
      final ad = a.data()['createdAt'];
      final bd = b.data()['createdAt'];
      final at = ad is Timestamp ? ad.millisecondsSinceEpoch : 0;
      final bt = bd is Timestamp ? bd.millisecondsSinceEpoch : 0;
      return bt.compareTo(at);
    });
    return docs;
  }

  void _reload() => setState(() => _orders = _load());

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('طلباتي على السريع'),
      actions: [
        IconButton(onPressed: _reload, icon: const Icon(Icons.refresh), tooltip: 'تحديث'),
      ],
    ),
    body: FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _orders,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(child: Text('تعذر تحميل الطلبات. اضغط تحديث وحاول تاني.'));
        }
        if (!snapshot.hasData) return const Center(child: CircularProgressIndicator());
        final docs = snapshot.data!;
        if (docs.isEmpty) return const Center(child: Text('لسه مفيش طلبات سريعة'));
        return RefreshIndicator(
          onRefresh: () async {
            final next = _load();
            setState(() => _orders = next);
            await next;
          },
          child: ListView.separated(
            padding: AppSpacing.pagePadding,
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final status = (data['status'] ?? '').toString();
              return _QuickOrderTile(
                data: data,
                status: status,
                onTap: () async {
                  await Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => QuickOrderCustomerDetailPage(orderId: doc.id),
                  ));
                  if (mounted) _reload();
                },
              );
            },
          ),
        );
      },
    ),
  );
}

/// كارت طلب سريع: الحالة والوقت وملخص الأصناف، من غير أكواد أو أرقام داخلية.
class _QuickOrderTile extends StatelessWidget {
  const _QuickOrderTile({required this.data, required this.status, required this.onTap});

  final Map<String, dynamic> data;
  final String status;
  final VoidCallback onTap;

  static String _when(Object? value) {
    if (value is! Timestamp) return '';
    final d = value.toDate().toLocal();
    final now = DateTime.now();
    final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
    final time = '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'ص' : 'م'}';
    final sameDay = d.year == now.year && d.month == now.month && d.day == now.day;
    return sameDay ? 'النهارده $time' : '${d.day}/${d.month} • $time';
  }

  String get _summary {
    final stores = data['stores'];
    if (stores is! List || stores.isEmpty) return '';
    final parts = <String>[];
    for (final raw in stores) {
      if (raw is! Map) continue;
      final items = (raw['items'] ?? '').toString().trim();
      if (items.isNotEmpty) parts.add(items.replaceAll('\n', '، '));
      if (raw['pricedItems'] is List) {
        for (final line in raw['pricedItems'] as List) {
          if (line is Map && line['name'] != null) parts.add('${line['name']}');
        }
      }
    }
    return parts.join('، ');
  }

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (status) {
      'delivered' => (AppColors.successSoft, AppColors.success),
      'cancelled' || 'canceled' => (AppColors.dangerSoft, AppColors.danger),
      'summary_pending' => (AppColors.orangeSoft, AppColors.orangeDeep),
      _ => (AppColors.purpleSoft, AppColors.purple),
    };
    final when = _when(data['createdAt']);
    final summary = _summary;
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: AppColors.orangeSoft,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: const Icon(Icons.bolt_rounded, color: AppColors.orange),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      const Expanded(
                        child: Text('طلب سريع', style: TextStyle(
                          fontSize: AppTypography.body,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        )),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
                        decoration: BoxDecoration(
                          color: bg,
                          borderRadius: BorderRadius.circular(AppRadius.pill),
                        ),
                        child: Text(quickOrderStatusLabel(status), style: TextStyle(
                          color: fg,
                          fontSize: AppTypography.caption,
                          fontWeight: FontWeight.w800,
                        )),
                      ),
                    ]),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(summary, maxLines: 1, overflow: TextOverflow.ellipsis,
                          style: AppTypography.secondary),
                    ],
                    if (when.isNotEmpty)
                      Text(when, style: AppTypography.secondary.copyWith(fontSize: AppTypography.caption)),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_left_rounded, color: AppColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}
