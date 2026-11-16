import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/dialogs.dart';

/// إدارة المناديب: إضافة، إيقاف/تفعيل، وحذف. بتكتب مباشرة في couriers/{uid}
/// والقواعد (firestore.rules) هي اللي بتسمح للمدير فقط.
class AdminRolesPage extends StatefulWidget {
  const AdminRolesPage({super.key});

  @override
  State<AdminRolesPage> createState() => _AdminRolesPageState();
}

class _AdminRolesPageState extends State<AdminRolesPage> {
  final _uid = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance.collection('couriers').limit(200).snapshots();
  bool _busy = false;

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('couriers');

  @override
  void dispose() {
    _uid.dispose();
    _name.dispose();
    _phone.dispose();
    super.dispose();
  }

  void _toast(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _add() async {
    if (_busy) return;
    final uid = _uid.text.trim();
    final name = _name.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{20,40}$').hasMatch(uid)) {
      _toast('الـ UID غير صحيح. انسخه كامل من Firebase.');
      return;
    }
    if (name.isEmpty) {
      _toast('اكتب اسم المندوب.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _col.doc(uid).set({
        'name': name,
        'phone': _phone.text.trim(),
        'active': true,
      }, SetOptions(merge: true));
      _uid.clear();
      _name.clear();
      _phone.clear();
      _toast('تمت إضافة المندوب.');
    } on FirebaseException catch (e) {
      _toast(
        e.code == 'permission-denied'
            ? 'مفيش صلاحية. تأكد إنك مدير.'
            : 'تعذر الحفظ. جرّب تاني.',
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(String id, bool active) async {
    try {
      await _col.doc(id).update({'active': active});
    } on FirebaseException {
      _toast('تعذر التعديل. جرّب تاني.');
    }
  }

  Future<void> _delete(String id, String name) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف مندوب',
      message: 'حذف "$name" نهائيًا؟ (الإيقاف أنسب لو هيرجع تاني)',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _col.doc(id).delete();
    } on FirebaseException {
      _toast('تعذر الحذف. جرّب تاني.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('إدارة المناديب')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text(
            'خد الـ UID بتاع المندوب من Firebase Console ثم Authentication ثم Users '
            '(عمود User UID). المندوب لازم يكون سجّل دخول التطبيق مرة.',
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _uid,
            textDirection: TextDirection.ltr,
            decoration: const InputDecoration(labelText: 'UID المندوب'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _name,
            decoration: const InputDecoration(labelText: 'الاسم'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'الموبايل (اختياري)'),
          ),
          const SizedBox(height: 16),
          _busy
              ? Center(child: CircularProgressIndicator(color: kPrimary))
              : FilledButton(onPressed: _add, child: const Text('إضافة مندوب')),
          const SizedBox(height: 24),
          Text(
            'المناديب الحاليين',
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stream,
            builder: (context, snap) {
              if (snap.hasError) {
                return const Text('تعذر تحميل المناديب.');
              }
              if (!snap.hasData) {
                return Center(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: CircularProgressIndicator(color: kPrimary),
                  ),
                );
              }
              final docs = snap.data!.docs;
              if (docs.isEmpty) return const Text('مفيش مناديب لسه.');
              return Column(
                children: [
                  for (final d in docs)
                    Card(
                      child: ListTile(
                        title: Text((d.data()['name'] ?? 'مندوب').toString()),
                        subtitle: Text(
                          (d.data()['phone'] ?? '').toString().isEmpty
                              ? d.id
                              : '${d.data()['phone']}',
                        ),
                        leading: Switch(
                          value: (d.data()['active'] as bool?) ?? true,
                          onChanged: (v) => _toggle(d.id, v),
                        ),
                        trailing: IconButton(
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => _delete(
                            d.id,
                            (d.data()['name'] ?? 'مندوب').toString(),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
