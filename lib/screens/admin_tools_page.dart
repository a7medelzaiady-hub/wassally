import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'quick_price_admin_page.dart';
import '../services/catalog_service.dart';
import '../services/catalog_sync.dart';
import '../services/delivery_service.dart';
import '../services/promo_service.dart';
import '../services/read_meter.dart';
import '../services/store_highlights.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/app_header.dart';
import '../widgets/dialogs.dart';

String _err(Object e) => e is FirebaseException
    ? (e.code == 'permission-denied'
          ? 'مفيش صلاحية — انشر القواعد من Firebase Console'
          : e.code)
    : e.toString();

void _say(BuildContext c, String m) {
  if (!c.mounted) return;
  ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));
}

/// مركز إعدادات التشغيل للأدمن: مناطق التوصيل، كوبونات الخصم، والمشرفين.
class AdminToolsPage extends StatelessWidget {
  const AdminToolsPage({super.key});

  @override
  Widget build(BuildContext context) {
    Widget tile(IconData i, String t, String s, Widget page) => Card(
      child: ListTile(
        leading: Icon(i, color: kPrimary),
        title: Text(t, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Text(s),
        trailing: const Icon(Icons.chevron_left),
        onTap: () =>
            Navigator.of(context).push(MaterialPageRoute(builder: (_) => page)),
      ),
    );
    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'إعدادات التشغيل'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                tile(
                  Icons.message_outlined,
                  'رقم واتساب الدعم',
                  'تغيير رقم التواصل والشكاوى',
                  const AdminWhatsAppPage(),
                ),
                tile(
                  Icons.map_outlined,
                  'مناطق التوصيل',
                  'سعر توصيل لكل منطقة',
                  const AdminAreasPage(),
                ),
                tile(
                  Icons.local_offer_outlined,
                  'كوبونات الخصم',
                  'إضافة وإيقاف أكواد الخصم',
                  const AdminPromosPage(),
                ),
                tile(
                  Icons.supervisor_account_outlined,
                  'المشرفين',
                  'مشرف يدير مجموعة مناديب',
                  const AdminSupervisorsPage(),
                ),
                tile(
                  Icons.price_check_outlined,
                  'أسعار الطلبات السريعة التقريبية',
                  'إضافة وتعديل وحذف الأصناف والأسعار الإرشادية',
                  const QuickPriceAdminPage(),
                ),
                const _CatalogIndexCard(),
                const _HighlightsRefreshCard(),
                tile(
                  Icons.speed_outlined,
                  'عدّاد القراءات (تقديري)',
                  'كل شاشة جابت كام مستند من Firestore (للقياس)',
                  const AdminReadMeterPage(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── ملخص العروض ─────────────────────────

/// تحديث ملخص العروض (offerItems/bestItems) لكل المحلات على دفعات من 50 محل.
/// الرئيسية بتعرض العروض من الملخص ده، فاعمله مرة بعد التحديث أو لو عرض مش ظاهر صح.
class _HighlightsRefreshCard extends StatefulWidget {
  const _HighlightsRefreshCard();

  @override
  State<_HighlightsRefreshCard> createState() => _HighlightsRefreshCardState();
}

class _HighlightsRefreshCardState extends State<_HighlightsRefreshCard> {
  String? _cursor;
  int _total = 0;
  int _failed = 0;
  bool _busy = false;
  bool _finished = false;

  Future<void> _run() async {
    final ok = await confirmDialog(
      context,
      title: 'تحديث ملخص العروض',
      message:
          'هيتحدث ملخص العروض لـ 50 محل في المرة (كل محل بيقرا أصنافه اللي عليها عروض أو الأكثر مبيعًا بس). '
          'دوس تاني للدفعة اللي بعدها. تكمل؟',
      confirmLabel: 'ابدأ',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final r = await StoreHighlights.refreshBatch(
        startAfterId: _finished ? null : _cursor,
        // العروض في الرئيسية بتتقري من فهرس الكتالوج: نحدّث خانة كل محل بعد ملخصه.
        afterEach: CatalogSync.storeChanged,
      );
      await CatalogService.bump();
      if (!mounted) return;
      setState(() {
        if (_finished) {
          _total = 0;
          _failed = 0;
        }
        _total += r.done;
        _failed += r.failed;
        _cursor = r.lastId;
        _finished = r.lastId == null;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر التحديث: ${_err(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final failedNote = _failed == 0 ? '' : ' (فشل $_failed — شغّل التحديث تاني)';
    final status = _total == 0
        ? 'الرئيسية بتعرض العروض من الملخص ده من غير قراءة الأصناف'
        : _finished
            ? 'خلص: اتعالج $_total محل$failedNote'
            : 'اتعالج $_total محل$failedNote — دوس للدفعة الجاية';
    return Card(
      child: ListTile(
        leading: Icon(Icons.local_offer_outlined, color: kPrimary),
        title: const Text(
          'تحديث ملخص العروض',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(status),
        trailing: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        onTap: _busy ? null : _run,
      ),
    );
  }
}

// ───────────────────────── عدّاد القراءات ─────────────────────────

/// عرض تقريبي للقراءات اللي الجهاز ده جابها من الخادم من ساعة ما اتفتح التطبيق
/// (أو من آخر تصفير)، مقسمة حسب الشاشة/الخدمة. قراءات قواعد Firestore والـ Worker مش هنا.
class AdminReadMeterPage extends StatefulWidget {
  const AdminReadMeterPage({super.key});

  @override
  State<AdminReadMeterPage> createState() => _AdminReadMeterPageState();
}

class _AdminReadMeterPageState extends State<AdminReadMeterPage> {
  /// من مستند الإصدارات اللي الجلسة قرته أصلًا (من غير أي قراءة جديدة).
  static String _catalogHealth() {
    final v = CatalogReader.loadedVersions;
    if (v == null) {
      return 'حالة الكتالوج المجمّع: افتح الرئيسية مرة الأول عشان تظهر (من غير قراءة زيادة).';
    }
    if (v['indexReady'] != true) {
      return 'فهرس المحلات مش جاهز: كل العملاء على الطريقة القديمة (دوس «بناء فهرس الكتالوج»).';
    }
    final h = CatalogReader.disabledMenus(v);
    if (h.disabled == 0 && h.big == 0) return 'الكتالوج المجمّع: كل المحلات شغالة.';
    return 'كتالوجات متعطلة: ${h.disabled} محل على الطريقة القديمة'
        '${h.big > 0 ? ' (منهم ${h.big} أكبر من الحد)' : ''}. '
        'بتتصلح تلقائيًا مع أول تعديل صنف ناجح، أو بـ «بناء فهرس الكتالوج».';
  }

  @override
  Widget build(BuildContext context) {
    final rows = ReadMeter.snapshot();
    final since = ReadMeter.since;
    return Scaffold(
      body: Column(
        children: [
          const InnerHeader(title: 'عدّاد القراءات (تقديري)'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(16),
              children: [
                SwitchListTile(
                  value: ReadMeter.enabled,
                  onChanged: (v) => setState(() => ReadMeter.enabled = v),
                  title: const Text(
                    'تشغيل العدّاد على الجهاز ده',
                    style: TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: const Text(
                    'شغّله، واستخدم التطبيق زي العميل/المحل، وارجع هنا تشوف الأرقام.',
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'الإجمالي التقديري: ${ReadMeter.total()} قراءة منذ '
                  '${since.hour.toString().padLeft(2, '0')}:${since.minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16),
                ),
                const SizedBox(height: 4),
                Text(
                  _catalogHealth(),
                  style: TextStyle(color: kMuted, fontSize: 13),
                ),
                const SizedBox(height: 8),
                if (rows.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Text('لسه مفيش قراءات متسجلة.'),
                  ),
                for (final r in rows)
                  ListTile(
                    dense: true,
                    title: Text(r.key, textDirection: TextDirection.ltr),
                    trailing: Text(
                      '${r.value}',
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(() {}),
                        icon: const Icon(Icons.refresh),
                        label: const Text('تحديث'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => setState(ReadMeter.reset),
                        icon: const Icon(Icons.restart_alt),
                        label: const Text('تصفير'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'تقريبي: بيعدّ المستندات الجاية من الخادم بس (الكاش المحلي صفر). '
                  'دي قراءات تقديرية مرصودة من الجهاز ده للمقارنة بين الشاشات، '
                  'مش فاتورة Firebase. الرقم الرسمي (ومعاه قراءات قواعد الأمان '
                  'والـ Worker) في Firebase Console ← Usage.',
                  style: TextStyle(color: kMuted, fontSize: 12),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── فهرس الكتالوج ─────────────────────────

/// بناء الفهرس المجمّع وقوائم الأصناف من الصفر: أول مرة بعد التحديث، أو للإصلاح.
/// بيقرا كل المحلات وكل الأصناف مرة واحدة، فمش المفروض يتعمل كتير.
class _CatalogIndexCard extends StatefulWidget {
  const _CatalogIndexCard();

  @override
  State<_CatalogIndexCard> createState() => _CatalogIndexCardState();
}

class _CatalogIndexCardState extends State<_CatalogIndexCard> {
  bool _busy = false;
  String _status = '';

  Future<void> _run() async {
    final ok = await confirmDialog(
      context,
      title: 'بناء فهرس الكتالوج',
      message:
          'هيتقرا كل المحلات وكل الأصناف مرة واحدة ويتبني منهم الفهرس اللي '
          'بيوفّر القراءات على العملاء. اعمله مرة بعد التحديث، أو لو لاحظت محل '
          'أو صنف مش ظاهر صح. تكمل؟',
      confirmLabel: 'ابدأ',
    );
    if (!ok || !mounted) return;
    setState(() {
      _busy = true;
      _status = 'جاري البناء...';
    });
    try {
      final summary = await CatalogSync.rebuildAll(
        onProgress: (step) {
          if (mounted) setState(() => _status = step);
        },
      );
      if (mounted) setState(() => _status = summary);
    } catch (e) {
      if (mounted) setState(() => _status = 'فشل: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        leading: Icon(Icons.inventory_2_outlined, color: kPrimary),
        title: const Text(
          'بناء فهرس الكتالوج',
          style: TextStyle(fontWeight: FontWeight.w800),
        ),
        subtitle: Text(
          _status.isEmpty
              ? 'يقلل قراءات العملاء: المحلات في قراءة واحدة وأصناف كل محل في قراءة واحدة'
              : _status,
        ),
        trailing: _busy
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.refresh),
        onTap: _busy ? null : _run,
      ),
    );
  }
}

// ───────────────────────── مناطق التوصيل ─────────────────────────

class AdminAreasPage extends StatefulWidget {
  const AdminAreasPage({super.key});

  @override
  State<AdminAreasPage> createState() => _AdminAreasPageState();
}

class _AdminAreasPageState extends State<AdminAreasPage> {
  List<DeliveryArea>? _areas;
  bool _paused = false;

  @override
  void initState() {
    super.initState();
    DeliveryService.load(force: true).then((a) {
      if (mounted) {
        setState(() {
          _areas = List.of(a);
          _paused = DeliveryService.ordersPaused;
        });
      }
    });
  }

  Future<void> _togglePaused(bool paused) async {
    if (paused) {
      final ok = await confirmDialog(
        context,
        title: 'إيقاف الطلبات',
        message: 'العملاء مش هيقدروا يبعتوا طلبات جديدة لحد ما ترجّع التشغيل. الطلبات الحالية مش هتتأثر.',
        confirmLabel: 'إيقاف',
        destructive: true,
      );
      if (!mounted || !ok) return;
    }
    try {
      await DeliveryService.setOrdersPaused(paused);
      if (!mounted) return;
      setState(() => _paused = paused);
      _say(context, paused ? 'تم إيقاف استقبال الطلبات.' : 'تم تشغيل استقبال الطلبات.');
    } catch (e) {
      if (!mounted) return;
      _say(context, 'تعذر الحفظ: ${_err(e)}');
    }
  }

  Future<void> _save() async {
    try {
      await DeliveryService.save(_areas!);
      if (!mounted) return;
      _say(context, 'تم الحفظ.');
    } catch (e) {
      if (!mounted) return;
      _say(context, 'تعذر الحفظ: ${_err(e)}');
    }
  }

  Future<void> _edit([int? index]) async {
    final name = TextEditingController(
      text: index == null ? '' : _areas![index].name,
    );
    final fee = TextEditingController(
      text: index == null ? '' : _areas![index].fee.toStringAsFixed(0),
    );
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(index == null ? 'منطقة جديدة' : 'تعديل المنطقة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: name,
                decoration: const InputDecoration(labelText: 'اسم المنطقة'),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: fee,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'سعر التوصيل'),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok != true) return;
    final n = name.text.trim();
    final f = double.tryParse(fee.text.trim().replaceAll(',', '.'));
    if (n.isEmpty || n.length > 60 || f == null || f < 0 || f > 1000) {
      _say(context, 'اكتب اسم وسعر صحيحين.');
      return;
    }
    setState(() {
      if (index == null) {
        _areas!.add(DeliveryArea(n, f));
      } else {
        _areas![index] = DeliveryArea(n, f);
      }
    });
    await _save();
  }

  Future<void> _remove(int i) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف منطقة',
      message: 'حذف "${_areas![i].name}"؟',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!mounted || !ok) return;
    setState(() => _areas!.removeAt(i));
    await _save();
  }

  @override
  Widget build(BuildContext context) {
    final areas = _areas;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: areas == null ? null : () => _edit(),
        icon: const Icon(Icons.add),
        label: const Text('منطقة'),
      ),
      body: Column(
        children: [
          const InnerHeader(title: 'مناطق التوصيل'),
          Expanded(
            child: areas == null
                ? Center(child: CircularProgressIndicator(color: kPrimary))
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                    children: [
                      Card(
                        child: SwitchListTile(
                          title: const Text('إيقاف استقبال الطلبات مؤقتًا'),
                          subtitle: const Text('للطوارئ: العملاء مش هيقدروا يبعتوا طلبات جديدة.'),
                          value: _paused,
                          onChanged: _togglePaused,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        areas.isEmpty
                            ? 'لسه مفيش مناطق. العملاء بيدفعوا 20 جنيه توصيل. أول ما تضيف منطقة، العميل هيختار منطقته وقت الطلب.'
                            : 'العميل بيختار منطقته وقت الطلب وسعر التوصيل بيتحسب منها.',
                        style: TextStyle(color: kMuted),
                      ),
                      const SizedBox(height: 10),
                      for (var i = 0; i < areas.length; i++)
                        Card(
                          child: ListTile(
                            title: Text(areas[i].name),
                            subtitle: Text(formatPrice(areas[i].fee)),
                            onTap: () => _edit(i),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline),
                              onPressed: () => _remove(i),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── الكوبونات ─────────────────────────

class AdminPromosPage extends StatefulWidget {
  const AdminPromosPage({super.key});

  @override
  State<AdminPromosPage> createState() => _AdminPromosPageState();
}

class _AdminPromosPageState extends State<AdminPromosPage> {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('promos');

  Future<void> _add() async {
    final code = TextEditingController();
    final pct = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('كوبون جديد'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: code,
                textDirection: TextDirection.ltr,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(
                  labelText: 'الكود (حروف إنجليزي وأرقام)',
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: pct,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'نسبة الخصم % (من 1 لـ 50)',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok != true) return;
    final c = PromoService.normalize(code.text);
    final p = double.tryParse(pct.text.trim());
    if (c.length < 3 || c.length > 20 || p == null || p <= 0 || p > 50) {
      _say(context, 'كود (3 حروف أو أكتر) ونسبة من 1 لـ 50.');
      return;
    }
    try {
      await _col.doc(c).set({
        'percent': p,
        'active': true,
        'note': '',
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      if (!mounted) return;
      _say(context, 'تعذر الحفظ: ${_err(e)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('كوبون'),
      ),
      body: Column(
        children: [
          const InnerHeader(title: 'كوبونات الخصم'),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _col.limit(200).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('تعذر التحميل: ${_err(snap.error!)}'),
                  );
                }
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('مفيش كوبونات لسه.'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    for (final d in docs)
                      Card(
                        child: ListTile(
                          title: Text(
                            d.id,
                            textDirection: TextDirection.ltr,
                            textAlign: TextAlign.start,
                            style: const TextStyle(fontWeight: FontWeight.w800),
                          ),
                          subtitle: Text(
                            'خصم ${(d.data()['percent'] as num?)?.toStringAsFixed(0) ?? '?'}%',
                          ),
                          leading: Switch(
                            value: d.data()['active'] == true,
                            onChanged: (v) => d.reference
                                .update({
                                  'active': v,
                                  'updatedAt': FieldValue.serverTimestamp(),
                                })
                                .catchError((e) {
                                  if (!context.mounted) return;
                                  _say(context, 'تعذر التعديل: ${_err(e)}');
                                }),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                d.reference.delete().catchError((e) {
                                  if (!context.mounted) return;
                                  _say(context, 'تعذر الحذف: ${_err(e)}');
                                }),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ───────────────────────── المشرفين ─────────────────────────

class AdminSupervisorsPage extends StatefulWidget {
  const AdminSupervisorsPage({super.key});

  @override
  State<AdminSupervisorsPage> createState() => _AdminSupervisorsPageState();
}

class _AdminSupervisorsPageState extends State<AdminSupervisorsPage> {
  CollectionReference<Map<String, dynamic>> get _col =>
      FirebaseFirestore.instance.collection('supervisors');

  Future<void> _add() async {
    final uid = TextEditingController();
    final name = TextEditingController();
    final phone = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('مشرف جديد'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'الـ UID من Firebase Console ← Authentication ← Users. لازم يكون سجّل دخول التطبيق مرة.',
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: uid,
                  textDirection: TextDirection.ltr,
                  decoration: const InputDecoration(labelText: 'UID'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: 'الاسم'),
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: phone,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'الموبايل (اختياري)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );
    if (!mounted || ok != true) return;
    final id = uid.text.trim();
    if (!RegExp(r'^[A-Za-z0-9]{20,40}$').hasMatch(id) ||
        name.text.trim().isEmpty) {
      _say(context, 'UID غير صحيح أو الاسم فاضي.');
      return;
    }
    try {
      await _col.doc(id).set({
        'name': name.text.trim(),
        'phone': phone.text.trim(),
        'active': true,
      });
    } catch (e) {
      if (!mounted) return;
      _say(context, 'تعذر الحفظ: ${_err(e)}');
    }
  }

  Future<void> _assign(String supId, String supName) async {
    List<QueryDocumentSnapshot<Map<String, dynamic>>> couriers;
    try {
      couriers =
          (await FirebaseFirestore.instance
                  .collection('couriers')
                  .limit(200)
                  .get())
              .docs;
    } catch (e) {
      if (!mounted) return;
      _say(context, 'تعذر تحميل المناديب: ${_err(e)}');
      return;
    }
    if (!mounted) return;
    final mine = <String>{
      for (final c in couriers)
        if (c.data()['supervisorId'] == supId) c.id,
    };
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (ctx, setS) => SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.8,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Text(
                      'مناديب $supName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView(
                      shrinkWrap: true,
                      children: [
                        for (final c in couriers)
                          CheckboxListTile(
                            value: mine.contains(c.id),
                            title: Text(
                              (c.data()['name'] ?? 'مندوب').toString(),
                            ),
                            subtitle:
                                (c.data()['supervisorId'] != null &&
                                    c.data()['supervisorId'] != supId &&
                                    !mine.contains(c.id))
                                ? const Text('تابع لمشرف تاني')
                                : null,
                            onChanged: (v) async {
                              try {
                                await c.reference.update({
                                  'supervisorId': v == true
                                      ? supId
                                      : FieldValue.delete(),
                                });
                                setS(
                                  () => v == true
                                      ? mine.add(c.id)
                                      : mine.remove(c.id),
                                );
                              } catch (e) {
                                if (!mounted) return;
                                _say(context, 'تعذر التعديل: ${_err(e)}');
                              }
                            },
                          ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('مشرف'),
      ),
      body: Column(
        children: [
          const InnerHeader(title: 'المشرفين'),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _col.limit(100).snapshots(),
              builder: (context, snap) {
                if (snap.hasError) {
                  return Center(
                    child: Text('تعذر التحميل: ${_err(snap.error!)}'),
                  );
                }
                if (!snap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  );
                }
                final docs = snap.data!.docs;
                if (docs.isEmpty) {
                  return const Center(child: Text('مفيش مشرفين لسه.'));
                }
                return ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
                  children: [
                    for (final d in docs)
                      Card(
                        child: ListTile(
                          title: Text((d.data()['name'] ?? 'مشرف').toString()),
                          subtitle: const Text('اضغط لاختيار مناديبه'),
                          onTap: () => _assign(
                            d.id,
                            (d.data()['name'] ?? 'مشرف').toString(),
                          ),
                          leading: Switch(
                            value: d.data()['active'] != false,
                            onChanged: (v) => d.reference
                                .update({'active': v})
                                .catchError((e) {
                                  if (!context.mounted) return;
                                  _say(context, 'تعذر التعديل: ${_err(e)}');
                                }),
                          ),
                          trailing: IconButton(
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () =>
                                d.reference.delete().catchError((e) {
                                  if (!context.mounted) return;
                                  _say(context, 'تعذر الحذف: ${_err(e)}');
                                }),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

 
/// رقم دعم واحد للمحادثات والشكاوى. لا توجد مستمعات مستمرة.
class AdminWhatsAppPage extends StatefulWidget {
  const AdminWhatsAppPage({super.key});

  @override
  State<AdminWhatsAppPage> createState() => _AdminWhatsAppPageState();
}

class _AdminWhatsAppPageState extends State<AdminWhatsAppPage> {
  final _number = TextEditingController(text: '01000197222');
  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('app_info').doc('contact').get();
      final saved = (snap.data()?['whatsapp'] ?? '').toString().trim();
      if (saved.isNotEmpty) _number.text = saved;
    } catch (e) {
      if (mounted) _say(context, 'تعذر تحميل الرقم: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _save() async {
    final digits = _number.text.replaceAll(RegExp(r'[^0-9]'), '');
    if (!RegExp(r'^(01[0-9]{9}|201[0-9]{9})$').hasMatch(digits)) {
      _say(context, 'اكتب رقم موبايل مصري صحيح');
      return;
    }
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance.collection('app_info')
          .doc('contact').set({'whatsapp': digits}, SetOptions(merge: true));
      if (mounted) _say(context, 'تم حفظ رقم واتساب الدعم');
    } catch (e) {
      if (mounted) _say(context, 'تعذر حفظ الرقم: ${_err(e)}');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  void dispose() {
    _number.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Column(children: [
      const InnerHeader(title: 'رقم واتساب الدعم'),
      Expanded(child: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('الرقم ده هيستخدمه العميل للتواصل والشكاوى عبر واتساب.'),
        const SizedBox(height: 16),
        TextField(
          controller: _number,
          keyboardType: TextInputType.phone,
          enabled: !_loading && !_saving,
          decoration: const InputDecoration(
            labelText: 'رقم واتساب',
            hintText: '01000197222',
            border: OutlineInputBorder(),
          ),
        ),
        const SizedBox(height: 16),
        ElevatedButton(
          onPressed: _loading || _saving ? null : _save,
          child: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ الرقم'),
        ),
      ])),
    ]),
  );
}
