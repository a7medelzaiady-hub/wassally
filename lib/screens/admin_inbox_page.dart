import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../services/chat_service.dart';
import '../services/driver_service.dart';
import '../services/role_request_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import 'support_chat_page.dart';

typedef _Doc = QueryDocumentSnapshot<Map<String, dynamic>>;

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
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(text: 'طلبات الانضمام'),
              Tab(text: 'تقديمات المناديب'),
              Tab(text: 'المحادثات'),
              Tab(text: 'الشكاوى والاقتراحات'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _RequestsTab(),
            _ApplicantsTab(),
            _ChatsTab(),
            _ComplaintsTab(),
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

class _RequestsTab extends StatelessWidget {
  const _RequestsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // من غير orderBy عشان ما نحتاجش فهرس مركّب. الترتيب هنا في الكود.
      stream: FirebaseFirestore.instance
          .collection('role_requests')
          .where('status', isEqualTo: 'pending')
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
        final docs = [...snap.data!.docs]
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
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _RequestCard(doc: docs[i]),
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
      for (final d in stores.docs) d.id: (d.data()['name'] ?? d.id).toString(),
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
    ctrl.dispose();
    return result;
  }

  Future<void> _approve() async {
    final isStore = widget.doc.data()['type'] == JoinType.storeOwner.key;
    String? storeId;
    String? newStoreName;
    if (isStore) {
      final picked = await _pickStore();
      if (picked == null) return;
      storeId = picked.id;
      newStoreName = picked.name;
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
      'تم القبول. المستخدم يقفل التطبيق ويفتحه تاني.',
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
    controller.dispose();
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
                    fontWeight: FontWeight.w900,
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
class _ApplicantsTab extends StatelessWidget {
  const _ApplicantsTab();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // المراجعة مستمرة أولًا بأول؛ لا نخفي أي تقديم بسبب حد ثابت.
      stream: FirebaseFirestore.instance
          .collectionGroup('applicants')
          .snapshots(),
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
        final docs = [...snap.data!.docs]
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
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (_, i) => _ApplicantCard(doc: docs[i]),
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

/// محادثات المستخدمين مع الإدارة.
class _ChatsTab extends StatelessWidget {
  const _ChatsTab();

  static const _roles = {
    'courier': 'مندوب',
    'store_owner': 'صاحب محل',
    'customer': 'عميل',
    'admin': 'مدير',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: ChatService.watchAllChats(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'تعذر تحميل المحادثات',
            message: _errText(snap.error),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.forum_outlined,
            title: 'مفيش محادثات لسه',
            message: 'أي رسالة من المستخدمين هتظهر هنا.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final unread = m['unreadForAdmin'] == true;
            final name = (m['userName'] ?? '').toString().trim();
            final title = name.isEmpty
                ? ((m['userEmail'] ?? 'مستخدم').toString())
                : name;
            final role = _roles[(m['appRole'] ?? 'customer').toString()] ?? '';
            return Material(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(16),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) =>
                        SupportChatPage(chatUid: d.id, title: title),
                  ),
                ),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: unread ? kPrimary : kLine,
                      width: unread ? 1.5 : 1,
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                                if (role.isNotEmpty) ...[
                                  const SizedBox(width: 8),
                                  Text(
                                    role,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: kMuted,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              (m['lastMessage'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: unread
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: unread ? kInk : kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            _date(m['lastAt']),
                            style: TextStyle(fontSize: 11, color: kMuted),
                          ),
                          if (unread)
                            Container(
                              margin: const EdgeInsets.only(top: 6),
                              width: 10,
                              height: 10,
                              decoration: BoxDecoration(
                                color: kPrimary,
                                shape: BoxShape.circle,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _ComplaintsTab extends StatelessWidget {
  const _ComplaintsTab();

  static const _status = {
    'open': 'جديدة',
    'in_progress': 'قيد المراجعة',
    'resolved': 'تم الحل',
  };

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('complaints')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.hasError) {
          return EmptyState(
            icon: Icons.lock_outline,
            title: 'تعذر تحميل الشكاوى',
            message: _errText(snap.error),
          );
        }
        if (!snap.hasData) {
          return Center(child: CircularProgressIndicator(color: kPrimary));
        }
        final docs = snap.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'مفيش شكاوى أو اقتراحات',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 12),
          itemBuilder: (context, i) {
            final d = docs[i];
            final m = d.data();
            final kind = _kindLabel('${m['kind']}');
            final st = '${m['status'] ?? 'open'}';
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
                        label: Text(kind),
                        visualDensity: VisualDensity.compact,
                      ),
                      const Spacer(),
                      DropdownButton<String>(
                        value: _status.containsKey(st) ? st : 'open',
                        underline: const SizedBox.shrink(),
                        items: [
                          for (final e in _status.entries)
                            DropdownMenuItem(
                              value: e.key,
                              child: Text(e.value),
                            ),
                        ],
                        onChanged: (v) {
                          if (v != null) d.reference.update({'status': v});
                        },
                      ),
                    ],
                  ),
                  SelectableText('${m['message'] ?? ''}'),
                  if ('${m['adminNote'] ?? ''}'.isNotEmpty)
                    Container(
                      margin: const EdgeInsets.only(top: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kPrimarySoft,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('ردنا: ${m['adminNote']}'),
                    ),
                  Align(
                    alignment: AlignmentDirectional.centerEnd,
                    child: TextButton.icon(
                      onPressed: () => _reply(context, d),
                      icon: const Icon(Icons.reply, size: 18),
                      label: Text(
                        '${m['adminNote'] ?? ''}'.isEmpty
                            ? 'رد على العميل'
                            : 'تعديل الرد',
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    [
                      if ('${m['userName'] ?? ''}'.isNotEmpty)
                        '${m['userName']}',
                      if ('${m['userEmail'] ?? ''}'.isNotEmpty)
                        '${m['userEmail']}',
                      if ('${m['orderId'] ?? ''}'.isNotEmpty) 'بخصوص طلب',
                      if ('${m['appRole'] ?? ''}'.isNotEmpty) '${m['appRole']}',
                      _date(m['createdAt']),
                    ].where((e) => e.isNotEmpty).join(' · '),
                    style: TextStyle(color: kMuted, fontSize: 12),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static Future<void> _reply(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> d,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final m = d.data();
    final ctrl = TextEditingController(text: '${m['adminNote'] ?? ''}');
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('الرد على العميل'),
          content: TextField(
            controller: ctrl,
            maxLines: 4,
            maxLength: 300,
            decoration: const InputDecoration(hintText: 'اكتب ردك هنا'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
              child: const Text('إرسال الرد'),
            ),
          ],
        ),
      ),
    );
    if (text == null || text.isEmpty) return;
    try {
      await d.reference.update({
        'adminNote': text,
        'status': 'resolved',
        'resolvedAt': FieldValue.serverTimestamp(),
      });
      final uid = '${m['userId'] ?? ''}';
      if (uid.isNotEmpty) {
        await FirebaseFirestore.instance.collection('notifications').add({
          'userId': uid,
          'title': 'رد الإدارة على رسالتك',
          'body': text,
          'orderId': '',
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      messenger.showSnackBar(const SnackBar(content: Text('تم إرسال الرد.')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('تعذر إرسال الرد: $e')));
    }
  }

  static String _kindLabel(String k) => switch (k) {
    'suggestion' => 'اقتراح',
    'order_issue' => 'مشكلة في طلب',
    _ => 'شكوى',
  };
}
