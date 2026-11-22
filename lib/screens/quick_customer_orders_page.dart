import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/brand.dart';
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
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 10),
            itemBuilder: (context, index) {
              final doc = docs[index];
              final status = (doc.data()['status'] ?? '').toString();
              return Card(
                child: ListTile(
                  leading: Icon(Icons.flash_on, color: Brand.green),
                  title: Text('طلب سريع #${doc.id.length > 8 ? doc.id.substring(0, 8) : doc.id}'),
                  subtitle: Text(QuickOrderCustomerDetailPageStatus.label(status)),
                  trailing: const Icon(Icons.chevron_left),
                  onTap: () async {
                    await Navigator.of(context).push(MaterialPageRoute<void>(
                      builder: (_) => QuickOrderCustomerDetailPage(orderId: doc.id),
                    ));
                    if (mounted) _reload();
                  },
                ),
              );
            },
          ),
        );
      },
    ),
  );
}

/// ترجمة حالات الطلب بدون عرض رموز الـWorker للعميل.
class QuickOrderCustomerDetailPageStatus {
  static String label(String status) => switch (status) {
    'open' => 'بانتظار مندوب',
    'accepted' => 'المندوب استلم الطلب',
    'purchasing' => 'المندوب بيشتري طلبك',
    'summary_pending' => 'راجع الحساب النهائي',
    'summary_approved' => 'تمت الموافقة على الحساب',
    'delivered' => 'تم التسليم',
    'cancelled' => 'ملغي',
    _ => 'جارٍ متابعة الطلب',
  };
}
