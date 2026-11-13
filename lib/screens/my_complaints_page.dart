import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/empty_state.dart';
import '../widgets/app_header.dart';

/// شكاوى واقتراحات العميل وردود الإدارة عليها.
class MyComplaintsPage extends StatelessWidget {
  const MyComplaintsPage({super.key});

  static const _status = {
    'open': 'وصلت للإدارة',
    'in_progress': 'قيد المراجعة',
    'resolved': 'تم الرد',
  };

  static String _kind(String k) => switch (k) {
    'suggestion' => 'اقتراح',
    'order_issue' => 'مشكلة في طلب',
    _ => 'شكوى',
  };

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'شكاواي واقتراحاتي'),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('complaints')
                  .where('userId', isEqualTo: uid)
                  .limit(50)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.lock_outline,
                    title: 'تعذر تحميل رسائلك',
                    message: 'جرّب تاني بعد شوية.',
                  );
                }
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  );
                }
                final docs = snap.data!.docs.toList()
                  ..sort((a, b) {
                    final x = a.data()['createdAt'];
                    final y = b.data()['createdAt'];
                    if (x is Timestamp && y is Timestamp) return y.compareTo(x);
                    return 0;
                  });
                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.inbox_outlined,
                    title: 'مفيش رسائل لسه',
                    message:
                        'أي شكوى أو اقتراح هتبعته هيظهر هنا مع رد الإدارة.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final m = docs[i].data();
                    final reply = '${m['adminNote'] ?? ''}';
                    final st = '${m['status'] ?? 'open'}';
                    final ts = m['createdAt'];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kLine),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Chip(
                                label: Text(_kind('${m['kind']}')),
                                visualDensity: VisualDensity.compact,
                              ),
                              const Spacer(),
                              Text(
                                _status[st] ?? 'وصلت للإدارة',
                                style: TextStyle(
                                  color: st == 'resolved' ? kSuccess : kMuted,
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12.5,
                                ),
                              ),
                            ],
                          ),
                          Text('${m['message'] ?? ''}'),
                          if (ts is Timestamp)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Text(
                                formatDateTime(ts.toDate()),
                                style: TextStyle(color: kMuted, fontSize: 12),
                              ),
                            ),
                          if (reply.isNotEmpty)
                            Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(top: 10),
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kPrimarySoft,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'رد الإدارة',
                                    style: TextStyle(
                                      color: kPrimary,
                                      fontWeight: FontWeight.w800,
                                      fontSize: 12.5,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(reply),
                                ],
                              ),
                            ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
