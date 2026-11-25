import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../widgets/app_header.dart';

import '../services/admin_inbox_counts.dart';
import '../services/notifications_query.dart';
import '../services/customer_rating_service.dart';
import '../services/driver_service.dart';
import '../services/role_request_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../utils/dialog_controllers.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

/// اسم التبويب ومعاه عدد اللي محتاج مراجعة (لو فيه).
class _CountLabel extends StatelessWidget {
  final String text;
  final int Function(AdminInboxCounts) pick;
  const _CountLabel(this.text, this.pick);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<AdminInboxCounts>(
      future: AdminInboxCounts.load(),
      builder: (context, snap) {
        final n = snap.data == null ? 0 : pick(snap.data!);
        if (n == 0) return Text(text);
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text),
            const SizedBox(width: 6),
            Badge(
              label: Text(AdminInboxCounts.badgeText(n)),
              backgroundColor: const Color(0xFFD32F2F),
            ),
          ],
        );
      },
    );
  }
}

/// صندوق المدير: طلبات الانضمام (قبول/رفض) والشكاوى والاقتراحات.
class AdminInboxPage extends StatelessWidget {
  const AdminInboxPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('الطلبات والرسائل'),
          actions: const [HomeActionButton()],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            // Tabs sit on the purple app bar.
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: AppColors.orange,
            dividerColor: Colors.transparent,
            tabs: [
              Tab(child: _CountLabel('طلبات الانضمام', (c) => c.joinRequests)),
              const Tab(text: 'تقديمات المناديب'),
              const Tab(text: 'تقييم العملاء'),
              Tab(child: _CountLabel('تعذر التسليم', (c) => c.deliveryIssues)),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RequestsTab(),
            _ApplicantsTab(),
            _CustomerRatingsTab(),
            _DeliveryIssuesTab(),
          ],
        ),
      ),
    );
  }
}

String _errText(Object? e) => e is FirebaseException
    ? 'السبب: ${e.code}. لو permission-denied يبقى لازم تنشر firestore.rules الجديدة.'
    : 'حاول تاني بعد شوية.';

String _date(dynamic ts) => ts is Timestamp ? formatDateTime(ts.toDate()) : '';

class _RequestsTab extends StatefulWidget {
  const _RequestsTab();

  @override
  State<_RequestsTab> createState() => _RequestsTabState();
}

class _RequestsTabState extends State<_RequestsTab> {
  static const int _pageSize = 100;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _moreDocs = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  Future<void> _loadMore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> firstPage,
  ) async {
    if (_loadingMore || !_hasMore) return;
    final cursor = _moreDocs.isNotEmpty
        ? _moreDocs.last
        : (firstPage.isNotEmpty ? firstPage.last : null);
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await FirebaseFirestore.instance
          .collection('role_requests')
          .where('status', isEqualTo: 'pending')
          .startAfterDocument(cursor)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      final known = {...firstPage.map((d) => d.reference.path), ..._moreDocs.map((d) => d.reference.path)};
      setState(() {
        _moreDocs.addAll(page.docs.where((d) => !known.contains(d.reference.path)));
        _hasMore = page.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
      debugPrint('Load more role requests: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // أول 100 طلب فقط تظل لحظية؛ الصفحات التالية تُقرأ مرة واحدة عند الطلب.
      stream: FirebaseFirestore.instance
          .collection('role_requests')
          .where('status', isEqualTo: 'pending')
          .limit(_pageSize)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'تعذر تحميل الطلبات',
            message: _errText(snap.error),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final docs = [...snap.data!.docs, ..._moreDocs]
          ..sort((a, b) {
            final x = a.data()['createdAt'];
            final y = b.data()['createdAt'];
            if (x is! Timestamp || y is! Timestamp) return 0;
            return y.compareTo(x);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.how_to_reg_outlined,
            title: 'مفيش طلبات انضمام معلّقة',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => i == docs.length
              ? TextButton(
                  onPressed: _loadingMore ? null : () => _loadMore(snap.data!.docs),
                  child: Text(_loadingMore ? 'جارٍ التحميل...' : 'تحميل المزيد من الطلبات'),
                )
              : _RequestCard(doc: docs[i]),
        );
      },
    );
  }
}

class _RequestCard extends StatefulWidget {
  final _Doc doc;
  const _RequestCard({required this.doc});

  @override
  State<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends State<_RequestCard> {
  bool _busy = false;

  /// نافذة ربط صاحب المحل: اكتب اسم المحل (محل جديد)، أو اضغط على محل موجود يظهر تحت.
  Future<({String? id, String name})?> _pickStore() async {
    final stores = await FirebaseFirestore.instance.collection('stores').limit(100).get();
    if (!mounted) return null;
    final existing = {
      for (final d in stores.docs)
        if ((d.data()['active'] as bool?) == true &&
            d.data()['approved'] != false)
          d.id: (d.data()['name'] ?? d.id).toString(),
    };
    final ctrl = TextEditingController(
      text: '${widget.doc.data()['storeName'] ?? ''}'.trim(),
    );
    String? chosenId;
    final result = await showDialog<({String? id, String name})>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) {
          final q = ctrl.text.trim().toLowerCase();
          final matches = [
            for (final e in existing.entries)
              if (q.isNotEmpty && e.value.toLowerCase().contains(q)) e,
          ].take(5).toList();
          final name = ctrl.text.trim();
          return AlertDialog(
            title: const Text('اسم المحل'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextField(
                    controller: ctrl,
                    decoration: const InputDecoration(
                      labelText: 'اكتب اسم المحل',
                      prefixIcon: Icon(Icons.storefront_outlined),
                    ),
                    onChanged: (_) => setS(() => chosenId = null),
                  ),
                  const SizedBox(height: 10),
                  if (matches.isNotEmpty) ...[
                    Text(
                      'محلات موجودة بنفس الاسم (اضغط للربط بيها):',
                      style: TextStyle(fontSize: 12, color: kMuted),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final e in matches)
                          ActionChip(
                            label: Text(e.value),
                            onPressed: () => setS(() {
                              ctrl.text = e.value;
                              chosenId = e.key;
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (name.isNotEmpty)
                    Text(
                      chosenId != null
                          ? 'هيتربط بالمحل الموجود "$name".'
                          : 'هيتعمل محل جديد باسم "$name" وتكمّل بياناته وصورته من "المحلات والأصناف".',
                      style: const TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء'),
              ),
              TextButton(
                onPressed: name.isEmpty
                    ? null
                    : () => Navigator.pop(ctx, (id: chosenId, name: name)),
                child: const Text('قبول'),
              ),
            ],
          );
        },
      ),
    );
    disposeAfterDialogCloses(ctrl);
    return result;
  }

  Future<void> _approve() async {
    final isStore = widget.doc.data()['type'] == JoinType.storeOwner.key;
    String? storeId;
    String? newStoreName;
    if (isStore) {
      final draftId = (widget.doc.data()['storeId'] ?? '').toString();
      if (draftId.isNotEmpty) {
        final ok = await confirmDialog(
          context,
          title: 'قبول المحل',
          message:
              'هيتم اعتماد المحل. هيظهر للعملاء تلقائيًا فقط لو فيه صورة و5 أصناف على الأقل؛ غير كده هيفضل مخفي لحد ما الإدارة تفعّله.',
          confirmLabel: 'اعتماد المحل',
        );
        if (!ok) return;
        storeId = draftId;
      } else {
        final picked = await _pickStore();
        if (picked == null) return;
        storeId = picked.id;
        newStoreName = picked.name;
      }
    } else {
      final ok = await confirmDialog(
        context,
        title: 'قبول المندوب',
        message: 'هيتضاف كمندوب نشط ويقدر يتقدّم على الطلبات.',
        confirmLabel: 'قبول',
      );
      if (!ok) return;
    }
    await _run(
      () => RoleRequestService.approve(
        widget.doc,
        storeId: storeId,
        newStoreName: newStoreName,
      ),
      'تم القبول وتحديث صلاحيات المستخدم.',
    );
  }

  Future<void> _reject() async {
    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
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
                hintText: 'اكتب سبب الرفض ليصل لصاحب الطلب...',
                border: OutlineInputBorder(),
              ),
              validator: (value) => (value ?? '').trim().length < 5
                  ? 'سبب الرفض يجب ألا يقل عن 5 أحرف'
                  : null,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: kDanger),
              onPressed: () {
                if (formKey.currentState?.validate() ?? false) {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: const Text('تأكيد الرفض'),
            ),
          ],
        ),
      ),
    );
    disposeAfterDialogCloses(controller);
    if (reason == null) return;
    await _run(
      () => RoleRequestService.reject(widget.doc, note: reason),
      'تم رفض الطلب وتسجيل السبب.',
    );
  }

  Future<void> _run(Future<void> Function() f, String done) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await f();
      messenger.showSnackBar(SnackBar(content: Text(done)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر التنفيذ. تأكد من الصلاحيات.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    final type = JoinType.parse(m['type']?.toString());
    Widget line(IconData i, String v) => v.isEmpty
        ? const SizedBox.shrink()
        : Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(i, size: 17, color: kMuted),
                const SizedBox(width: 8),
                Expanded(child: SelectableText(v)),
              ],
            ),
          );
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
              Expanded(
                child: Text(
                  '${m['name'] ?? ''}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ),
              Chip(
                label: Text(type?.label ?? '—'),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          line(Icons.phone_outlined, '${m['phone'] ?? ''}'),
          line(Icons.email_outlined, '${m['userEmail'] ?? ''}'),
          line(Icons.storefront_outlined, '${m['storeName'] ?? ''}'),
          if (type == JoinType.storeOwner)
            line(Icons.category_outlined, 'نوع النشاط: ${m['storeCategory'] ?? 'غير محدد (طلب قديم)'}'),
          line(Icons.location_on_outlined, '${m['address'] ?? ''}'),
          if (type == JoinType.storeOwner) ...[
            line(Icons.photo_outlined, 'صورة المحل: ${m['storeImageUrl'] ?? ''}'),
            line(Icons.badge_outlined, 'السجل التجاري: ${m['registrationNumber'] ?? 'غير مرفق'}'),
            line(Icons.verified_outlined, 'إثبات النشاط: ${m['proofUrl'] ?? 'غير مرفق'}'),
            line(Icons.store_mall_directory_outlined, 'تليفون المحل: ${(m['storePhone'] ?? '').toString().trim().isEmpty ? 'غير مرفق' : m['storePhone']}'),
          ],
          line(Icons.two_wheeler, '${m['vehicle'] ?? ''}'),
          line(Icons.sticky_note_2_outlined, '${m['notes'] ?? ''}'),
          line(Icons.schedule, _date(m['createdAt'])),
          const SizedBox(height: 10),
          if (_busy)
            Center(child: CircularProgressIndicator(color: kPrimary))
          else
            Row(
              children: [
                Expanded(
                  child: FilledButton(
                    onPressed: _approve,
                    child: const Text('قبول'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton(
                    onPressed: _reject,
                    style: OutlinedButton.styleFrom(foregroundColor: kDanger),
                    child: const Text('رفض'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

/// كل تقديمات المناديب على الطلبات اللي لسه من غير مندوب. المدير يختار ويعيّن من هنا.
class _ApplicantsTab extends StatefulWidget {
  const _ApplicantsTab();

  @override
  State<_ApplicantsTab> createState() => _ApplicantsTabState();
}

class _ApplicantsTabState extends State<_ApplicantsTab> {
  bool _unorderedFallback = false;
  static const int _pageSize = 100;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _moreDocs = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  Future<void> _loadMore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> firstPage,
  ) async {
    if (_loadingMore || !_hasMore) return;
    final cursor = _moreDocs.isNotEmpty
        ? _moreDocs.last
        : (firstPage.isNotEmpty ? firstPage.last : null);
    if (cursor == null) return;
    setState(() => _loadingMore = true);
    // من غير الفهرس مفيش صفحات تانية مرتبة؛ أول 100 بس.
    if (_unorderedFallback) {
      setState(() => _hasMore = false);
      return;
    }
    try {
      final page = await FirebaseFirestore.instance
          .collectionGroup('applicants')
          .orderBy('createdAt', descending: true)
          .startAfterDocument(cursor)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      final known = {...firstPage.map((d) => d.reference.path), ..._moreDocs.map((d) => d.reference.path)};
      setState(() {
        _moreDocs.addAll(page.docs.where((d) => !known.contains(d.id)));
        _hasMore = page.docs.length == _pageSize;
        _loadingMore = false;
      });
    } catch (e) {
      if (mounted) setState(() => _loadingMore = false);
      debugPrint('Load more applicants: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // أول 100 تقديم تظل لحظية؛ الصفحات التالية تُقرأ مرة واحدة عند الطلب.
      // الاستعلام المرتّب محتاج فهرس collection group على createdAt (متعرّف في
      // firestore.indexes.json). لحد ما يتنشر: نفس الاستعلام من غير ترتيب وبنفس الحد،
      // والترتيب بيحصل هنا (من غير مستمع زيادة).
      stream: withIndexFallback(
        FirebaseFirestore.instance
            .collectionGroup('applicants')
            .orderBy('createdAt', descending: true)
            .limit(_pageSize)
            .snapshots(),
        () {
          _unorderedFallback = true;
          return FirebaseFirestore.instance
              .collectionGroup('applicants')
              .limit(_pageSize)
              .snapshots();
        },
        label: 'applicants',
      ),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'تعذر تحميل التقديمات',
            message: _errText(snap.error),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final docs = [...snap.data!.docs, ..._moreDocs]
          ..sort((a, b) {
            final x = a.data()['createdAt'];
            final y = b.data()['createdAt'];
            if (x is! Timestamp || y is! Timestamp) return 0;
            return y.compareTo(x);
          });
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.two_wheeler_outlined,
            title: 'مفيش تقديمات من مناديب دلوقتي',
            message: 'لما مندوب يقدّم على توصيل طلب هتلاقيه هنا.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length + (_hasMore ? 1 : 0),
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => i == docs.length
              ? TextButton(
                  onPressed: _loadingMore ? null : () => _loadMore(snap.data!.docs),
                  child: Text(_loadingMore ? 'جارٍ التحميل...' : 'تحميل المزيد من التقديمات'),
                )
              : _ApplicantCard(doc: docs[i]),
        );
      },
    );
  }
}

class _ApplicantCard extends StatefulWidget {
  final _Doc doc;
  const _ApplicantCard({required this.doc});

  @override
  State<_ApplicantCard> createState() => _ApplicantCardState();
}

class _ApplicantCardState extends State<_ApplicantCard> {
  bool _busy = false;

  String get _orderId => widget.doc.reference.parent.parent?.id ?? '';

  Future<void> _assign() async {
    final m = widget.doc.data();
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.assignCourier(
        _orderId,
        Courier(
          id: (m['courierId'] ?? widget.doc.id).toString(),
          name: (m['courierName'] ?? 'مندوب').toString(),
          phone: (m['courierPhone'] ?? '').toString(),
        ),
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تعيين المندوب.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            e is FirebaseException
                ? 'تعذر التعيين (${e.code}).'
                : 'تعذر التعيين.',
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = widget.doc.data();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('orders')
          .doc(_orderId)
          .snapshots(),
      builder: (context, snap) {
        final o = snap.data?.data();
        // الطلب اتعيّن له مندوب خلاص أو اتقفل: ما نعرضش التقديم.
        if (o != null &&
            ((o['courierId'] ?? '').toString().isNotEmpty ||
                (o['status'] ?? '') != 'preparing')) {
          return const SizedBox.shrink();
        }
        final store = (o?['storeName'] ?? 'طلب').toString();
        return Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: kLine),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                (m['courierName'] ?? 'مندوب').toString(),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              FutureBuilder<RatingSummary?>(
                future: RatingService.courier(
                  (m['courierId'] ?? widget.doc.id).toString(),
                ),
                builder: (context, rs) => Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    rs.data == null
                        ? 'التقييم: ...'
                        : 'التقييم: ${rs.data!.text}',
                    style: TextStyle(fontSize: 12.5, color: kMuted),
                  ),
                ),
              ),
              if ((m['courierPhone'] ?? '').toString().isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    (m['courierPhone']).toString(),
                    style: TextStyle(fontSize: 12.5, color: kMuted),
                  ),
                ),
              const SizedBox(height: 8),
              Text(
                'قدّم على توصيل: $store',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_date(m['createdAt']).isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: Text(
                    _date(m['createdAt']),
                    style: TextStyle(fontSize: 12, color: kMuted),
                  ),
                ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 44,
                child: FilledButton(
                  onPressed: _busy ? null : _assign,
                  child: const Text(
                    'تعيينه لتوصيل الطلب',
                    style: TextStyle(fontSize: 14),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _CustomerRatingsTab extends StatelessWidget {
  const _CustomerRatingsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: CustomerRatingService.watchAllReviews(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'تعذر تحميل تقييمات العملاء',
            message: _errText(snap.error),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.star_outline_rounded,
            title: 'لا توجد تقييمات للعملاء حتى الآن',
            message: 'تقييمات المندوبين وأصحاب المحلات ستظهر هنا بعد اكتمال الطلبات.',
          );
        }
        // لا نسمح بتقييد العميل بسبب تقييم واحد أو بسبب تقييمين لنفس الطلب.
        // نعدّ الطلبات المختلفة ذات التقييم <= 2، بعد استبعاد ما راجعته الإدارة.
        // العد هنا محافظ ومبني على آخر 100 مراجعة المعروضة.
        final lowRatingOrdersByCustomer = <String, Set<String>>{};
        for (final review in docs) {
          final data = review.data();
          final customerId = (data['customerId'] ?? '').toString();
          final orderId = (data['orderId'] ?? '').toString();
          final rating = (data['rating'] as num?)?.toInt() ?? 0;
          final excluded = data['moderationStatus'] == 'excluded';
          if (!excluded && rating <= 2 && customerId.isNotEmpty && orderId.isNotEmpty) {
            lowRatingOrdersByCustomer.putIfAbsent(customerId, () => <String>{}).add(orderId);
          }
        }
        // مستمع واحد للتقييدات النشطة بدل قراءة مستند تقييد منفصل لكل تقييم.
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('customer_restrictions')
              .where('active', isEqualTo: true)
              .limit(100)
              .snapshots(),
          builder: (context, restrictionsSnap) {
            final restricted = <String>{};
            for (final d in restrictionsSnap.data?.docs ?? const []) {
              final expiry = d.data()['expiresAt'];
              if (expiry is Timestamp && expiry.toDate().isAfter(DateTime.now())) {
                restricted.add(d.id);
              }
            }
            return ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: docs.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, index) {
                final doc = docs[index];
                final customerId = (doc.data()['customerId'] ?? '').toString();
                return _CustomerReviewCard(
                  doc: doc,
                  isRestricted: restricted.contains(customerId),
                  lowRatingOrderCount: lowRatingOrdersByCustomer[customerId]?.length ?? 0,
                );
              },
            );
          },
        );
      },
    );
  }
}

class _CustomerReviewCard extends StatefulWidget {
  final _Doc doc;
  final bool isRestricted;
  final int lowRatingOrderCount;
  const _CustomerReviewCard({
    required this.doc,
    required this.isRestricted,
    required this.lowRatingOrderCount,
  });

  @override
  State<_CustomerReviewCard> createState() => _CustomerReviewCardState();
}

class _CustomerReviewCardState extends State<_CustomerReviewCard> {
  bool _busy = false;

  Future<void> _moderate(String reviewId, {required bool exclude}) async {
    final controller = TextEditingController(
      text: exclude ? 'تمت مراجعة التقييم واستبعاده من الاعتداد به.' : 'تمت مراجعة الاعتراض وإعادة التقييم.',
    );
    final note = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: Text(exclude ? 'استبعاد التقييم؟' : 'إعادة التقييم؟'),
          content: TextField(
            controller: controller,
            minLines: 2,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'سبب قرار الإدارة',
              border: OutlineInputBorder(),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().length >= 5) {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: const Text('حفظ القرار'),
            ),
          ],
        ),
      ),
    );
    disposeAfterDialogCloses(controller);
    if (note == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await CustomerRatingService.moderateReview(
        reviewId: widget.doc.id,
        note: note,
        exclude: exclude,
      );
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر حفظ قرار المراجعة: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _warn(String customerId, String orderId, String detail) async {
    final ok = await confirmDialog(
      context,
      title: 'إرسال تنبيه للعميل؟',
      message: 'سيصل للعميل تنبيه لتحسين الالتزام بالتواصل والعنوان والاستلام.',
      confirmLabel: 'إرسال التنبيه',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await CustomerRatingService.warnCustomer(
        customerId: customerId,
        orderId: orderId,
        detail: detail,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال التنبيه للعميل.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر إرسال التنبيه: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restrict(String customerId, String orderId, String detail) async {
    // حاجز واجهة إضافي: لا تقييد بسبب تقييم منفرد أو تقييمات مرتبطة بطلب واحد.
    if (widget.lowRatingOrderCount < 2) return;
    final controller = TextEditingController(
      text: 'مراجعة وقائع متكررة في طلبات مختلفة: $detail',
    );
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('سبب التقييد المؤقت'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'تم رصد تقييمات منخفضة في ${widget.lowRatingOrderCount} طلبات مختلفة ضمن آخر 100 مراجعة. '
                'راجع تفاصيل كل واقعة وتأكد من عدم وجود خطأ أو اعتراض قبل فرض أي تقييد.',
                style: const TextStyle(fontSize: 12.5),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: controller,
                minLines: 2,
                maxLines: 4,
                maxLength: 300,
                decoration: const InputDecoration(
                  hintText: 'اكتب الوقائع التي راجعتها الإدارة وسبب القرار',
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().length >= 5) {
                  Navigator.pop(ctx, controller.text.trim());
                }
              },
              child: const Text('تقييد 3 أيام'),
            ),
          ],
        ),
      ),
    );
    disposeAfterDialogCloses(controller);
    if (reason == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await CustomerRatingService.restrictCustomer(
        customerId: customerId,
        sourceOrderId: orderId,
        reason: reason,
        durationDays: 3,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم فرض تقييد مؤقت بعد مراجعة الإدارة.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر فرض التقييد: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _lift(String customerId) async {
    final ok = await confirmDialog(
      context,
      title: 'رفع التقييد؟',
      message: 'السماح للعميل بإنشاء الطلبات مرة أخرى.',
      confirmLabel: 'رفع التقييد',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await CustomerRatingService.liftRestriction(customerId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم رفع التقييد.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر رفع التقييد: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final customerId = (data['customerId'] ?? '').toString();
    final orderId = (data['orderId'] ?? '').toString();
    final rating = (data['rating'] as num?)?.toInt() ?? 0;
    final role = data['reviewerRole'] == 'courier' ? 'المندوب' : 'صاحب المحل';
    final reason = CustomerRatingService.reasonLabels[
          (data['reason'] ?? '').toString()
        ] ??
        'سبب غير محدد';
    final comment = (data['comment'] ?? '').toString();
    final moderationStatus = (data['moderationStatus'] ?? '').toString();

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
              Expanded(
                child: Text(
                  'تقييم العميل: $rating / 5',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Chip(
                label: Text(role),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text('العميل: $customerId', style: const TextStyle(fontSize: 12)),
          Text('الطلب: $orderId', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text('السبب: $reason'),
          if (comment.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text('ملاحظة: $comment'),
          ],
          const SizedBox(height: 4),
          Text(_date(data['createdAt']), style: TextStyle(color: kMuted, fontSize: 12)),
          if (moderationStatus == 'excluded') ...[
            const SizedBox(height: 8),
            const Text(
              'هذا التقييم مستبعد من الاعتداد به بعد مراجعة الإدارة.',
              style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w800),
            ),
            Text(
              'قرار الإدارة: ${data['adminNote'] ?? ''}',
              style: const TextStyle(fontSize: 12),
            ),
            TextButton(
              onPressed: _busy ? null : () => _moderate(widget.doc.id, exclude: false),
              child: const Text('إعادة التقييم للاعتداد به'),
            ),
          ] else ...[
            const Divider(height: 18),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton.icon(
                onPressed: _busy ? null : () => _moderate(widget.doc.id, exclude: true),
                icon: const Icon(Icons.visibility_off_outlined),
                label: const Text('استبعاد التقييم بعد المراجعة'),
              ),
            ),
          ],
          if (moderationStatus == 'excluded')
            const Text(
              'لا يتم اتخاذ إجراء تجاه العميل اعتمادًا على تقييم مستبعد.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            )
          else if (widget.isRestricted)
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'العميل عليه تقييد مؤقت',
                    style: TextStyle(color: Colors.red, fontWeight: FontWeight.w800),
                  ),
                ),
                TextButton(
                  onPressed: _busy ? null : () => _lift(customerId),
                  child: const Text('رفع التقييد'),
                ),
              ],
            )
          else if (rating <= 2 && customerId.isNotEmpty && orderId.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: _busy
                      ? null
                      : () => _warn(customerId, orderId, reason),
                  icon: const Icon(Icons.notifications_active_outlined),
                  label: const Text('إرسال تحذير'),
                ),
                if (widget.lowRatingOrderCount >= 2)
                  FilledButton.tonalIcon(
                    onPressed: _busy
                        ? null
                        : () => _restrict(customerId, orderId, reason),
                    icon: const Icon(Icons.gpp_maybe_outlined),
                    label: const Text('مراجعة التقييد لمدة 3 أيام'),
                  )
                else
                  const Text(
                    'تنبيه ومراجعة فقط: لا يُتاح التقييد قبل تكرار الوقائع في طلبات مختلفة ومراجعتها يدويًا.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
              ],
            )
          else
            const Text(
              'لا يوجد إجراء تلقائي. التقييمات المنخفضة فقط تُعرض للمراجعة.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          if (_busy)
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

class _DeliveryIssuesTab extends StatelessWidget {
  const _DeliveryIssuesTab();

  static const _reasons = {
    'no_answer': 'العميل لا يرد',
    'wrong_address': 'العنوان غير صحيح',
    'refused_order': 'رفض الاستلام',
    'no_cash': 'لا يملك قيمة الطلب النقدي',
    'customer_requested_delay': 'طلب تأجيل التسليم',
    'unsafe_location': 'المكان غير آمن',
    'other': 'سبب آخر',
  };

  static const _statuses = {
    'open': 'جديدة',
    'in_review': 'قيد المراجعة',
    'retry': 'إعادة محاولة معتمدة',
    'return_to_store': 'مطلوب إرجاعه للمحل',
    'returned_to_store': 'بانتظار تأكيد المحل',
    'store_confirmed_return': 'المحل أكد استلام المرتجع',
    'resolved': 'تم الحل',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('delivery_issues')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'تعذر تحميل بلاغات التسليم',
            message: _errText(snap.error),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.delivery_dining_outlined,
            title: 'لا توجد بلاغات تعذر تسليم',
            message: 'عند تسجيل المندوب مشكلة في الوصول للعميل ستظهر هنا.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, index) => _DeliveryIssueCard(doc: docs[index]),
        );
      },
    );
  }
}

class _DeliveryIssueCard extends StatefulWidget {
  final _Doc doc;
  const _DeliveryIssueCard({required this.doc});

  @override
  State<_DeliveryIssueCard> createState() => _DeliveryIssueCardState();
}

class _DeliveryIssueCardState extends State<_DeliveryIssueCard> {
  bool _busy = false;

  Future<void> _decide(String status) async {
    final orderId = (widget.doc.data()['orderId'] ?? '').toString();
    final decision = switch (status) {
      'in_review' => 'الإدارة بدأت مراجعة تعذر التسليم.',
      'retry' => 'الإدارة وافقت على إعادة محاولة التسليم بعد التواصل مع العميل.',
      'return_to_store' => 'الإدارة طلبت إعادة الطلب إلى المحل.',
      'store_confirmed_return' => 'الإدارة اعتمدت استلام المحل للمرتجع بعد المراجعة.',
      _ => 'تم تحديث البلاغ.',
    };
    final labels = {
      'in_review': 'بدء المراجعة',
      'retry': 'إعادة المحاولة',
      'return_to_store': 'إرجاع للمحل',
      'store_confirmed_return': 'اعتماد استلام المحل',
    };
    final ok = await confirmDialog(
      context,
      title: labels[status] ?? 'تحديث البلاغ',
      message: decision,
      confirmLabel: labels[status] ?? 'تأكيد',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await StaffOrderService.decideDeliveryIssue(
        issueId: widget.doc.id,
        orderId: orderId,
        status: status,
        decision: decision,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إرسال قرار الإدارة للمندوب والعميل.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تعذر تحديث البلاغ: $error')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.doc.data();
    final status = (data['status'] ?? 'open').toString();
    final reason = _DeliveryIssuesTab._reasons[(data['reason'] ?? '').toString()] ?? 'سبب غير محدد';
    final orderId = (data['orderId'] ?? '').toString();
    final courierId = (data['courierId'] ?? '').toString();
    final customerId = (data['customerId'] ?? '').toString();
    final note = (data['note'] ?? '').toString();
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
              Expanded(
                child: Text(
                  'بلاغ تعذر التسليم',
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                ),
              ),
              Chip(
                label: Text(_DeliveryIssuesTab._statuses[status] ?? status),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          Text('الطلب: $orderId', style: const TextStyle(fontSize: 12)),
          Text('المندوب: $courierId', style: const TextStyle(fontSize: 12)),
          Text('العميل: $customerId', style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 6),
          Text('السبب: $reason'),
          if (note.isNotEmpty) Text('ملاحظة المندوب: $note'),
          Text(_date(data['createdAt']), style: TextStyle(color: kMuted, fontSize: 12)),
          if (status == 'open' || status == 'in_review') ...[
            const Divider(height: 18),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (status == 'open')
                  OutlinedButton(
                    onPressed: _busy ? null : () => _decide('in_review'),
                    child: const Text('قيد المراجعة'),
                  ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _decide('retry'),
                  child: const Text('إعادة المحاولة'),
                ),
                FilledButton.tonal(
                  onPressed: _busy ? null : () => _decide('return_to_store'),
                  child: const Text('إرجاع للمحل'),
                ),
              ],
            ),
          ] else if (status == 'returned_to_store') ...[
            const SizedBox(height: 8),
            const Text(
              'المندوب أكد رجوع الطلب. انتظر تأكيد صاحب المحل لاستلام المرتجع.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: OutlinedButton(
                onPressed: _busy ? null : () => _decide('store_confirmed_return'),
                child: const Text('اعتماد استلام المحل إداريًا'),
              ),
            ),
          ] else if (status == 'store_confirmed_return') ...[
            const SizedBox(height: 8),
            const Text(
              'تم تأكيد استلام المحل للمرتجع. يمكنك الآن إغلاق الطلب من لوحة الإدارة.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
          if (_busy) const Padding(
            padding: EdgeInsets.only(top: 8),
            child: LinearProgressIndicator(),
          ),
        ],
      ),
    );
  }
}
