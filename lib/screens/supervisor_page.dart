import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback_fab.dart';
import '../widgets/staff_header.dart';

/// لوحة المشرف: المناديب المربوطين بيه (الأدمن هو اللي بيربطهم)، مع تقييم كل واحد،
/// وزر اتصال، وتفعيل/إيقاف المندوب.
class SupervisorPage extends StatelessWidget {
  final String name;
  const SupervisorPage({super.key, this.name = ''});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return Scaffold(
      floatingActionButton: const FeedbackFab(),
      body: Column(
        children: [
          StaffHeader(
            title: 'لوحة المشرف',
            subtitle: name.isEmpty ? 'مناديبك' : 'أهلاً $name',
          ),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('couriers')
                  .where('supervisorId', isEqualTo: uid)
                  .snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return const EmptyState(
                    icon: Icons.lock_outline,
                    title: 'تعذر تحميل المناديب',
                    message: 'اتأكد إن القواعد منشورة وإن حسابك مضاف كمشرف.',
                  );
                }
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const EmptyState(
                    icon: Icons.two_wheeler,
                    title: 'مفيش مناديب مربوطين بيك',
                    message: 'الإدارة هي اللي بتربط المناديب بيك.',
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final n = (m['ratingCount'] as num?)?.toInt() ?? 0;
                    final sum = (m['ratingSum'] as num?)?.toDouble() ?? 0;
                    final phone = (m['phone'] ?? '').toString();
                    final active = m['active'] != false;
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: kLine),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (m['name'] ?? 'مندوب').toString(),
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 15,
                                  ),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  n == 0
                                      ? 'بدون تقييم'
                                      : 'تقييم ${(sum / n).toStringAsFixed(1)} ($n)',
                                  style: TextStyle(
                                    color: kMuted,
                                    fontSize: 12.5,
                                  ),
                                ),
                                Text(
                                  active ? 'شغّال' : 'موقوف',
                                  style: TextStyle(
                                    color: active ? kSuccess : kDanger,
                                    fontWeight: FontWeight.w700,
                                    fontSize: 12.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (phone.isNotEmpty)
                            IconButton(
                              icon: Icon(Icons.call, color: kPrimary),
                              onPressed: () async {
                                final uri = Uri.parse('tel:$phone');
                                if (await canLaunchUrl(uri)) {
                                  await launchUrl(uri);
                                }
                              },
                            ),
                          Switch(
                            value: active,
                            onChanged: (v) async {
                              final messenger = ScaffoldMessenger.of(context);
                              try {
                                await d.reference.update({'active': v});
                              } catch (_) {
                                messenger.showSnackBar(
                                  const SnackBar(
                                    content: Text('تعذر التعديل.'),
                                  ),
                                );
                              }
                            },
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
