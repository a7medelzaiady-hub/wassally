import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

import '../services/role_request_service.dart';
import '../theme/app_theme.dart';
import '../utils/dialog_controllers.dart';

/// مراجعة طلبات الانضمام. صلاحية القراءة والقرار محمية أيضًا بقواعد Firestore.
class AdminJoinRequestsPage extends StatefulWidget {
  const AdminJoinRequestsPage({super.key});

  @override
  State<AdminJoinRequestsPage> createState() => _AdminJoinRequestsPageState();
}

class _AdminJoinRequestsPageState extends State<AdminJoinRequestsPage> {
  final Set<String> _busyIds = <String>{};

  void _message(String value) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(value)));
  }

  Future<void> _approve(QueryDocumentSnapshot<Map<String, dynamic>> request) async {
    if (_busyIds.contains(request.id)) return;
    setState(() => _busyIds.add(request.id));
    try {
      final data = request.data();
      final type = JoinType.parse(data['type']?.toString());
      await RoleRequestService.approve(
        request,
        newStoreName: type == JoinType.storeOwner
            ? (data['storeName'] ?? '').toString()
            : null,
      );
      _message('تم قبول الطلب وتفعيل الحساب.');
    } catch (e) {
      _message('تعذر قبول الطلب: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(request.id));
    }
  }

  Future<void> _reject(QueryDocumentSnapshot<Map<String, dynamic>> request) async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('سبب رفض الطلب'),
          content: Form(
            key: formKey,
            child: TextFormField(
              controller: controller,
              autofocus: true,
              minLines: 2,
              maxLines: 4,
              maxLength: 300,
              decoration: const InputDecoration(
                hintText: 'اكتب سبب الرفض ليظهر لصاحب الطلب...',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value ?? '').trim().length < 5
                  ? 'اكتب سببًا واضحًا (5 أحرف على الأقل)'
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(dialogContext, controller.text.trim());
                }
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
    disposeAfterDialogCloses(controller);
    if (reason == null || _busyIds.contains(request.id)) return;

    setState(() => _busyIds.add(request.id));
    try {
      await RoleRequestService.reject(request, note: reason);
      _message('تم رفض الطلب وإرسال سبب الرفض إلى سجل الطلب.');
    } catch (e) {
      _message('تعذر رفض الطلب: $e');
    } finally {
      if (mounted) setState(() => _busyIds.remove(request.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('طلبات الانضمام'), actions: const [HomeActionButton()]),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: RoleRequestService.watchPending(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل الطلبات. تأكد من صلاحيات الأدمن.'));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final docs = [...snapshot.data!.docs]
            ..sort((a, b) {
              final ad = a.data()['createdAt'];
              final bd = b.data()['createdAt'];
              final at = ad is Timestamp ? ad : Timestamp(0, 0);
              final bt = bd is Timestamp ? bd : Timestamp(0, 0);
              return bt.compareTo(at);
            });
          if (docs.isEmpty) {
            return const Center(child: Text('لا توجد طلبات انضمام معلقة حاليًا.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final request = docs[index];
              final data = request.data();
              final type = JoinType.parse(data['type']?.toString());
              final isStore = type == JoinType.storeOwner;
              final busy = _busyIds.contains(request.id);
              final name = (data['name'] ?? 'بدون اسم').toString();
              return Card(
                elevation: 1,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        CircleAvatar(
                          backgroundColor: kPrimary.withValues(alpha: .12),
                          child: Icon(isStore ? Icons.storefront : Icons.delivery_dining, color: kPrimary),
                        ),
                        const SizedBox(width: 10),
                        Expanded(child: Text(name, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17))),
                        Chip(label: Text(type?.label ?? 'طلب غير معروف')),
                      ]),
                      const SizedBox(height: 10),
                      _detail('الهاتف', (data['phone'] ?? '').toString()),
                      if ((data['userEmail'] ?? '').toString().isNotEmpty)
                        _detail('البريد', (data['userEmail'] ?? '').toString()),
                      if (isStore) ...[
                        _detail('اسم المحل', (data['storeName'] ?? '').toString()),
                        _detail('نوع النشاط', (data['storeCategory'] ?? 'غير محدد (طلب قديم)').toString()),
                        _detail('العنوان', (data['address'] ?? '').toString()),
                      ] else if (type == JoinType.courier) ...[
                        _detail('وسيلة التوصيل', (data['vehicle'] ?? '').toString()),
                      ],
                      if ((data['notes'] ?? '').toString().trim().isNotEmpty)
                        _detail('ملاحظات', (data['notes'] ?? '').toString()),
                      const SizedBox(height: 14),
                      if (busy)
                        const Center(child: Padding(
                          padding: EdgeInsets.all(8),
                          child: CircularProgressIndicator(),
                        ))
                      else
                        Row(children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: () => _reject(request),
                              icon: const Icon(Icons.close, color: Colors.red),
                              label: const Text('رفض'),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton.icon(
                              onPressed: type == null ? null : () => _approve(request),
                              icon: const Icon(Icons.check),
                              label: const Text('قبول'),
                            ),
                          ),
                        ]),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _detail(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      SizedBox(width: 105, child: Text('$label:', style: TextStyle(color: Colors.grey.shade600))),
      Expanded(child: Text(value.isEmpty ? '—' : value)),
    ]),
  );
}
