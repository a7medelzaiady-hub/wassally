import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/dialogs.dart';

/// إدارة أصحاب المحلات (للمدير): ربط حساب بمحل، إيقاف/تفعيل، وحذف.
/// بتكتب في storeOwners/{uid}، والقواعد بتسمح للمدير فقط.
/// كل صاحب محل مربوط بمحل واحد. المدير يفضل يتحكم في كل المحلات.
class AdminStoreOwnersPage extends StatefulWidget {
  const AdminStoreOwnersPage({super.key});

  @override
  State<AdminStoreOwnersPage> createState() => _AdminStoreOwnersPageState();
}

class _AdminStoreOwnersPageState extends State<AdminStoreOwnersPage> {
  final _uid = TextEditingController();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  String? _storeId;
  bool _busy = false;

  late final Stream<QuerySnapshot<Map<String, dynamic>>> _owners =
      FirebaseFirestore.instance.collection('storeOwners').snapshots();
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stores =
      FirebaseFirestore.instance.collection('stores').snapshots();

  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('storeOwners');

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
    final storeId = _storeId;
    if (!RegExp(r'^[A-Za-z0-9]{20,40}$').hasMatch(uid)) {
      _toast('الـ UID غير صحيح. انسخه كامل من Firebase.');
      return;
    }
    if (name.isEmpty) {
      _toast('اكتب اسم صاحب المحل.');
      return;
    }
    if (storeId == null) {
      _toast('اختار المحل.');
      return;
    }
    setState(() => _busy = true);
    try {
      await _col.doc(uid).set({
        'name': name,
        'phone': _phone.text.trim(),
        'storeId': storeId,
        'active': true,
      });
      _uid.clear();
      _name.clear();
      _phone.clear();
      setState(() => _storeId = null);
      _toast('تم ربط الحساب بالمحل. لازم يقفل التطبيق ويفتحه تاني.');
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
      title: 'إزالة صاحب محل',
      message:
          'إزالة "$name"؟ الحساب هيرجع عميل عادي. (الإيقاف أنسب لو هيرجع تاني)',
      confirmLabel: 'إزالة',
      destructive: true,
    );
    if (!ok) return;
    try {
      await _col.doc(id).delete();
    } on FirebaseException {
      _toast('تعذر الإزالة. جرّب تاني.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('أصحاب المحلات')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _stores,
        builder: (context, storesSnap) {
          final storeNames = <String, String>{};
          for (final d in storesSnap.data?.docs ?? const []) {
            storeNames[d.id] = (d.data()['name'] ?? d.id).toString();
          }
          final ids = storeNames.keys.toList()
            ..sort((a, b) => storeNames[a]!.compareTo(storeNames[b]!));

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              const Text(
                'خد الـ UID بتاع صاحب المحل من Firebase Console ثم Authentication '
                'ثم Users (عمود User UID). لازم يكون سجّل دخول التطبيق مرة. '
                'صاحب المحل بيدير أصناف محله وطلباته وفتحه وقفله، '
                'والمدير بيفضل يتحكم في كل حاجة.',
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _uid,
                textDirection: TextDirection.ltr,
                decoration: const InputDecoration(labelText: 'UID صاحب المحل'),
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
                decoration: const InputDecoration(
                  labelText: 'الموبايل (اختياري)',
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                key: ValueKey('store-$_storeId'),
                initialValue: ids.contains(_storeId) ? _storeId : null,
                decoration: const InputDecoration(labelText: 'المحل'),
                items: [
                  for (final id in ids)
                    DropdownMenuItem(value: id, child: Text(storeNames[id]!)),
                ],
                onChanged: (v) => setState(() => _storeId = v),
              ),
              const SizedBox(height: 16),
              _busy
                  ? Center(child: CircularProgressIndicator(color: kPrimary))
                  : FilledButton(
                      onPressed: _add,
                      child: const Text('ربط صاحب محل'),
                    ),
              const SizedBox(height: 24),
              Text(
                'أصحاب المحلات الحاليين',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 8),
              StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                stream: _owners,
                builder: (context, snap) {
                  if (snap.hasError) {
                    return const Text('تعذر تحميل أصحاب المحلات.');
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
                  if (docs.isEmpty) return const Text('مفيش أصحاب محلات لسه.');
                  return Column(
                    children: [
                      for (final d in docs)
                        Card(
                          child: ListTile(
                            title: Text(
                              (d.data()['name'] ?? 'صاحب محل').toString(),
                            ),
                            subtitle: Text(
                              'المحل: ${storeNames[d.data()['storeId']] ?? d.data()['storeId'] ?? '—'}',
                            ),
                            leading: Switch(
                              value: (d.data()['active'] as bool?) ?? true,
                              onChanged: (v) => _toggle(d.id, v),
                            ),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _delete(
                                d.id,
                                (d.data()['name'] ?? 'صاحب محل').toString(),
                              ),
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          );
        },
      ),
    );
  }
}
