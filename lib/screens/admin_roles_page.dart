import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';
import 'admin_user_directory_page.dart';

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
  String? _storeId;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream =
      FirebaseFirestore.instance.collection('couriers').limit(200).snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stores =
      FirebaseFirestore.instance.collection('stores').limit(200).snapshots();
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
        'storeId': _storeId ?? FieldValue.delete(),
      }, SetOptions(merge: true));
      _uid.clear();
      _name.clear();
      _phone.clear();
      setState(() => _storeId = null);
      _toast('تم حفظ المندوب وربطه بالمحل المحدد.');
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

  Future<void> _toggleQuick(String id, bool enabled) async {
    try {
      await _col.doc(id).update({'quickEnabled': enabled});
      _toast(enabled ? 'تم تفعيل صلاحية الطلبات السريعة.' : 'تم إيقاف صلاحية الطلبات السريعة.');
    } on FirebaseException catch (e) {
      _toast(e.code == 'permission-denied'
          ? 'مفيش صلاحية لتعديل المندوب. تأكد إنك مدير.'
          : 'تعذر تعديل صلاحية الطلبات السريعة. جرّب تاني.');
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
      appBar: AppBar(title: const Text('إدارة المناديب'), actions: const [HomeActionButton()]),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: ListTile(
              leading: const Icon(Icons.people_alt_outlined),
              title: const Text('دليل المستخدمين والصلاحيات'),
              subtitle: const Text('عرض الأسماء ونسخ UID بضغطة واحدة'),
              trailing: const Icon(Icons.chevron_left),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const AdminUserDirectoryPage()),
              ),
            ),
          ),
          const SizedBox(height: 16),
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
          const SizedBox(height: 12),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _stores,
            builder: (context, snapshot) {
              final stores = snapshot.data?.docs ?? const [];
              return DropdownButtonFormField<String>(
                key: ValueKey('courier-store-$_storeId'),
                initialValue: stores.any((d) => d.id == _storeId) ? _storeId : null,
                decoration: const InputDecoration(
                  labelText: 'المحل التابع له المندوب (اختياري)',
                  helperText: 'اتركه بدون اختيار لو المندوب خارجي.',
                ),
                items: [
                  for (final store in stores)
                    DropdownMenuItem<String>(
                      value: store.id,
                      child: Text((store.data()['name'] ?? store.id).toString()),
                    ),
                ],
                onChanged: (value) => setState(() => _storeId = value),
              );
            },
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
                    Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Card(
                        clipBehavior: Clip.antiAlias,
                        margin: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(14),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    radius: 23,
                                    backgroundColor: kPrimary.withValues(alpha: 0.10),
                                    child: Icon(Icons.delivery_dining, color: kPrimary),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          (d.data()['name'] ?? 'مندوب').toString(),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                          style: Theme.of(context).textTheme.titleMedium
                                              ?.copyWith(fontWeight: FontWeight.w800),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          (d.data()['storeId'] ?? '').toString().isEmpty
                                              ? 'مندوب خارجي'
                                              : 'مندوب تابع لمحل',
                                          style: Theme.of(context).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: 'حذف المندوب',
                                    icon: const Icon(Icons.delete_outline),
                                    onPressed: () => _delete(
                                      d.id,
                                      (d.data()['name'] ?? 'مندوب').toString(),
                                    ),
                                  ),
                                ],
                              ),
                              if ((d.data()['phone'] ?? '').toString().trim().isNotEmpty) ...[
                                const SizedBox(height: 8),
                                Row(
                                  children: [
                                    const Icon(Icons.phone_outlined, size: 17),
                                    const SizedBox(width: 8),
                                    Flexible(
                                      child: Text(
                                        d.data()['phone'].toString(),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                              const Divider(height: 24),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text('حساب المندوب', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  Switch(
                                    value: (d.data()['active'] as bool?) ?? true,
                                    onChanged: (v) => _toggle(d.id, v),
                                  ),
                                ],
                              ),
                              Row(
                                children: [
                                  const Expanded(
                                    child: Text('صلاحية الطلبات السريعة', style: TextStyle(fontWeight: FontWeight.w600)),
                                  ),
                                  Switch(
                                    value: d.data()['quickEnabled'] == true,
                                    onChanged: ((d.data()['active'] as bool?) ?? true)
                                        ? (v) => _toggleQuick(d.id, v)
                                        : null,
                                  ),
                                ],
                              ),
                            ],
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
