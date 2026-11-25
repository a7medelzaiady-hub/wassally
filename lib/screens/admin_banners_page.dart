import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

import '../services/catalog_service.dart';
import '../services/image_service.dart';
import '../theme/brand.dart';
import '../widgets/dialogs.dart';

CollectionReference<Map<String, dynamic>> get _banners =>
    FirebaseFirestore.instance.collection('banners');

String _errorText(Object e) =>
    e is FirebaseException && e.code == 'permission-denied'
    ? 'مفيش صلاحية. تأكد إنك مدير.'
    : 'تعذر الحفظ. تأكد من الاتصال وجرّب تاني.';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// التحكم في بوسترات الصفحة الرئيسية: إضافة، تغيير صورة، ترتيب، إخفاء، حذف.
class AdminBannersPage extends StatefulWidget {
  const AdminBannersPage({super.key});

  @override
  State<AdminBannersPage> createState() => _AdminBannersPageState();
}

class _AdminBannersPageState extends State<AdminBannersPage> {
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = _banners
      .limit(100)
      .snapshots();
  bool _busy = false;

  void _say(String m) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));
  }

  Future<void> _add(int nextOrder) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final url = await ImageService.pickAndUpload('banners');
      if (url != null) {
        await _banners.add({'image': url, 'order': nextOrder, 'active': true});
        await CatalogService.bump();
        _say('تمت إضافة البوستر.');
      }
    } catch (e) {
      _say('تعذر رفع الصورة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _replace(_Doc d) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final url = await ImageService.pickAndUpload('banners');
      if (url != null) {
        await _banners.doc(d.id).update({'image': url});
        await CatalogService.bump();
        _say('تم تغيير الصورة.');
      }
    } catch (e) {
      _say('تعذر رفع الصورة: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _toggle(_Doc d, bool v) async {
    try {
      await _banners.doc(d.id).update({'active': v});
      await CatalogService.bump();
    } catch (e) {
      _say(_errorText(e));
    }
  }

  Future<void> _move(List<_Doc> docs, int from, int to) async {
    if (to < 0 || to >= docs.length) return;
    final ids = [for (final d in docs) d.id];
    final id = ids.removeAt(from);
    ids.insert(to, id);
    final batch = FirebaseFirestore.instance.batch();
    for (var i = 0; i < ids.length; i++) {
      batch.update(_banners.doc(ids[i]), {'order': i});
    }
    try {
      await batch.commit();
      await CatalogService.bump();
    } catch (e) {
      _say(_errorText(e));
    }
  }

  Future<void> _delete(_Doc d) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف البوستر',
      message: 'متأكد إنك عايز تحذف البوستر ده؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await _banners.doc(d.id).delete();
      await CatalogService.bump();
    } catch (e) {
      _say(_errorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stream,
      builder: (context, snap) {
        final docs = [...?snap.data?.docs]
          ..sort(
            (a, b) => ((a.data()['order'] as num?) ?? 0).compareTo(
              (b.data()['order'] as num?) ?? 0,
            ),
          );
        final nextOrder = docs.isEmpty
            ? 0
            : docs
                      .map((d) => ((d.data()['order'] as num?) ?? 0).toInt())
                      .reduce((a, b) => a > b ? a : b) +
                  1;

        return Scaffold(
          backgroundColor: Brand.bg,
          appBar: AppBar(
            title: const Text('بوسترات الرئيسية'),
            actions: const [HomeActionButton()],
          ),
          floatingActionButton: FloatingActionButton.extended(
            onPressed: _busy ? null : () => _add(nextOrder),
            icon: _busy
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Brand.ink,
                    ),
                  )
                : const Icon(Icons.add_photo_alternate_outlined),
            label: const Text('إضافة بوستر'),
          ),
          body: snap.hasError
              ? const Center(child: Text('تعذر تحميل البوسترات.'))
              : !snap.hasData
              ? Center(child: CircularProgressIndicator(color: Brand.green))
              : docs.isEmpty
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(28),
                    child: Text(
                      'مفيش بوسترات لسه.\nاضغط "إضافة بوستر" وارفع صورة.\n'
                      'أفضل مقاس: 1200×585 تقريباً (عرضي).',
                      textAlign: TextAlign.center,
                      style: TextStyle(height: 1.6),
                    ),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
                  itemCount: docs.length,
                  itemBuilder: (context, i) {
                    final d = docs[i];
                    final m = d.data();
                    final active = (m['active'] as bool?) ?? true;
                    final url = (m['image'] ?? '').toString();
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Column(
                        children: [
                          Stack(
                            children: [
                              AspectRatio(
                                aspectRatio: 2.05,
                                child: Opacity(
                                  opacity: active ? 1 : 0.4,
                                  child: Image.network(
                                    url,
                                    fit: BoxFit.cover,
                                    width: double.infinity,
                                    errorBuilder: (_, _, _) => Container(
                                      color: Brand.green.withValues(
                                        alpha: 0.10,
                                      ),
                                      child: Icon(
                                        Icons.broken_image_outlined,
                                        color: Brand.green,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                              Positioned(
                                top: 10,
                                right: 10,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 10,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Brand.gold,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Text(
                                    '${i + 1}',
                                    style: TextStyle(
                                      fontWeight: FontWeight.w800,
                                      color: Brand.ink,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            child: Row(
                              children: [
                                Switch(
                                  value: active,
                                  activeThumbColor: Brand.green,
                                  onChanged: (v) => _toggle(d, v),
                                ),
                                Text(
                                  active ? 'ظاهر' : 'مخفي',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: active ? Brand.green : Colors.grey,
                                  ),
                                ),
                                const Spacer(),
                                IconButton(
                                  tooltip: 'تحريك للأول',
                                  icon: const Icon(Icons.arrow_upward_rounded),
                                  onPressed: i == 0
                                      ? null
                                      : () => _move(docs, i, i - 1),
                                ),
                                IconButton(
                                  tooltip: 'تحريك للآخر',
                                  icon: const Icon(
                                    Icons.arrow_downward_rounded,
                                  ),
                                  onPressed: i == docs.length - 1
                                      ? null
                                      : () => _move(docs, i, i + 1),
                                ),
                                IconButton(
                                  tooltip: 'تغيير الصورة',
                                  icon: const Icon(Icons.image_outlined),
                                  onPressed: () => _replace(d),
                                ),
                                IconButton(
                                  tooltip: 'حذف',
                                  icon: const Icon(
                                    Icons.delete_outline,
                                    color: Colors.red,
                                  ),
                                  onPressed: () => _delete(d),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
        );
      },
    );
  }
}
