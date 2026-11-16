import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/feedback_service.dart';
import '../services/order_service.dart';
import '../theme/app_theme.dart';
import 'glossy_fab.dart';
import '../utils/format.dart';

/// زر عائم (speed dial) للشكاوى والاقتراحات. بيفتح 3 اختيارات، وكل واحد بيفتح نافذة إرسال.
/// [allowOrderIssue] = false للمندوب وصاحب المحل (مفيش "طلباتي" عندهم).
class FeedbackFab extends StatefulWidget {
  final bool allowOrderIssue;
  const FeedbackFab({super.key, this.allowOrderIssue = false});

  @override
  State<FeedbackFab> createState() => _FeedbackFabState();
}

class _FeedbackFabState extends State<FeedbackFab> {
  bool _open = false;

  IconData _icon(FeedbackKind k) => switch (k) {
    FeedbackKind.complaint => Icons.report_gmailerrorred_outlined,
    FeedbackKind.suggestion => Icons.lightbulb_outline,
    FeedbackKind.orderIssue => Icons.receipt_long_outlined,
    FeedbackKind.restrictionAppeal => Icons.gavel_outlined,
  };

  Future<void> _pick(FeedbackKind k) async {
    setState(() => _open = false);
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) =>
          FeedbackSheet(initial: k, allowOrderIssue: widget.allowOrderIssue),
    );
  }

  @override
  Widget build(BuildContext context) {
    final kinds = [
      for (final k in FeedbackKind.values)
        if ((k != FeedbackKind.orderIssue || widget.allowOrderIssue) &&
            (k != FeedbackKind.restrictionAppeal || widget.allowOrderIssue)) k,
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        AnimatedSize(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          alignment: Alignment.bottomRight,
          child: _open
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    for (final k in kinds)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: FloatingActionButton.extended(
                          heroTag: 'fb_${k.key}',
                          elevation: 2,
                          backgroundColor: Colors.white,
                          foregroundColor: kPrimary,
                          onPressed: () => _pick(k),
                          icon: Icon(_icon(k)),
                          label: Text(k.label),
                        ),
                      ),
                  ],
                )
              : const SizedBox(width: 0, height: 0),
        ),
        GlossyFab(
          tooltip: 'شكوى أو اقتراح',
          icon: _open ? Icons.close_rounded : Icons.headset_mic_rounded,
          onPressed: () => setState(() => _open = !_open),
        ),
      ],
    );
  }
}

class FeedbackSheet extends StatefulWidget {
  final FeedbackKind initial;
  final bool allowOrderIssue;
  const FeedbackSheet({
    super.key,
    required this.initial,
    this.allowOrderIssue = false,
  });

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  final _form = GlobalKey<FormState>();
  final _msg = TextEditingController();
  late FeedbackKind _kind = widget.initial;
  String? _orderId;
  bool _busy = false;
  Future<List<AppOrder>>? _orders;
  final _orderQ = TextEditingController();
  final _orderFocus = FocusNode();

  /// كل طلبات العميل من السيرفر (مش من الكاش، عشان الكاش ممكن يكون فيه كام طلب بس).
  Future<List<AppOrder>> _loadOrders() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const [];
    List<AppOrder> list = const [];
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .where('userId', isEqualTo: uid)
          .get(const GetOptions(source: Source.server));
      list = [for (final d in snap.docs) AppOrder.fromMap(d.id, d.data())];
    } catch (_) {
      try {
        list = await OrderService.watchMyOrders().first;
      } catch (_) {
        return const [];
      }
    }
    list.sort(
      (a, b) => (b.createdAt ?? DateTime(2000)).compareTo(
        a.createdAt ?? DateTime(2000),
      ),
    );
    return list.take(100).toList();
  }

  String _orderLabel(AppOrder o) => [
    o.storeName.isEmpty ? 'طلب' : o.storeName,
    if (o.createdAt != null) formatDateTime(o.createdAt!),
  ].join(' · ');

  @override
  void initState() {
    super.initState();
    if (widget.allowOrderIssue) _orders = _loadOrders();
  }

  @override
  void dispose() {
    _msg.dispose();
    _orderQ.dispose();
    _orderFocus.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await FeedbackService.send(
        kind: _kind,
        message: _msg.text,
        orderId: _orderId,
      );
      nav.pop();
      messenger.showSnackBar(
        const SnackBar(content: Text('وصلتنا رسالتك، شكرًا ليك 💚')),
      );
    } on FirebaseException catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر الإرسال (${e.code}). جرّب تاني.')),
      );
    } catch (_) {
      if (!mounted) return;
      setState(() => _busy = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر الإرسال. جرّب تاني.')),
      );
    }
  }

  /// اختيار الطلب بالكتابة: اكتب اسم المحل أو رقم الطلب وهتظهر قايمة الطلبات المطابقة.
  Widget _orderPicker(List<AppOrder> list) {
    final q = _orderQ.text.trim().toLowerCase();
    final matches = _orderId != null
        ? const <AppOrder>[]
        : [
            for (final o in list)
              if (q.isEmpty || o.storeName.toLowerCase().contains(q)) o,
          ];
    final showList = _orderId == null && (_orderFocus.hasFocus || q.isNotEmpty);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextFormField(
          controller: _orderQ,
          focusNode: _orderFocus,
          decoration: InputDecoration(
            labelText: 'ابحث باسم المحل أو رقم الطلب',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: _orderId == null
                ? null
                : IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() {
                      _orderId = null;
                      _orderQ.clear();
                    }),
                  ),
          ),
          onTap: () => setState(() {}),
          onChanged: (_) => setState(() => _orderId = null),
          validator: (_) => _orderId == null ? 'اختار الطلب من القايمة' : null,
        ),
        if (showList) ...[
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxHeight: 230),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: kLine),
            ),
            child: matches.isEmpty
                ? Padding(
                    padding: EdgeInsets.all(14),
                    child: Text(
                      'مفيش طلب مطابق.',
                      style: TextStyle(color: kMuted),
                    ),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: matches.length,
                    separatorBuilder: (_, _) =>
                        Divider(height: 1, color: kLine),
                    itemBuilder: (_, i) {
                      final o = matches[i];
                      return ListTile(
                        dense: true,
                        leading: Icon(
                          Icons.storefront_outlined,
                          color: kPrimary,
                        ),
                        title: Text(
                          o.storeName.isEmpty ? 'طلب' : o.storeName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
                        subtitle: Text(
                          [
                            if (o.createdAt != null)
                              formatDateTime(o.createdAt!),
                          ].join(' · '),
                          style: TextStyle(fontSize: 12, color: kMuted),
                        ),
                        onTap: () {
                          setState(() {
                            _orderId = o.id;
                            _orderQ.text = _orderLabel(o);
                          });
                          _orderFocus.unfocus();
                        },
                      );
                    },
                  ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    final kinds = [
      for (final k in FeedbackKind.values)
        if ((k != FeedbackKind.orderIssue || widget.allowOrderIssue) &&
          (k != FeedbackKind.restrictionAppeal || widget.allowOrderIssue)) k,
    ];
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 18, 20, 20 + bottom),
      child: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: kLine,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'كلّمنا',
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w900),
              ),
              const SizedBox(height: 4),
              Text(
                'رأيك بيفرق معانا. هنراجع رسالتك ونرد في أقرب وقت.',
                style: TextStyle(color: kMuted),
              ),
              const SizedBox(height: 14),
              Wrap(
                spacing: 8,
                children: [
                  for (final k in kinds)
                    ChoiceChip(
                      label: Text(k.label),
                      selected: _kind == k,
                      onSelected: (_) => setState(() => _kind = k),
                    ),
                ],
              ),
              if (_kind == FeedbackKind.orderIssue) ...[
                const SizedBox(height: 12),
                FutureBuilder<List<AppOrder>>(
                  future: _orders,
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const LinearProgressIndicator();
                    }
                    final list = snap.data ?? const <AppOrder>[];
                    if (list.isEmpty) {
                      return Text(
                        'مفيش طلبات سابقة تختار منها.',
                        style: TextStyle(color: kMuted),
                      );
                    }
                    return _orderPicker(list);
                  },
                ),
              ],
              if (_kind == FeedbackKind.restrictionAppeal) ...[
                const SizedBox(height: 8),
                const Text(
                  'سيُربط اعتراضك تلقائيًا بقرار التقييد المسجل على حسابك، وستتمكن من متابعة رد الإدارة من «شكاواي واقتراحاتي».',
                  style: TextStyle(fontSize: 12.5, color: Colors.black54),
                ),
              ],
              const SizedBox(height: 12),
              TextFormField(
                controller: _msg,
                minLines: 4,
                maxLines: 6,
                maxLength: FeedbackService.maxLength,
                decoration: InputDecoration(
                  labelText: _kind == FeedbackKind.restrictionAppeal
                      ? 'اشرح سبب اعتراضك وأي معلومات تدعم طلب المراجعة'
                      : 'اكتب رسالتك',
                  alignLabelWithHint: true,
                ),
                validator: (v) =>
                    (v ?? '').trim().length < FeedbackService.minLength
                    ? 'اكتب ${FeedbackService.minLength} حروف على الأقل'
                    : null,
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _send,
                  icon: _busy
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Icon(Icons.send_rounded),
                  label: const Text('إرسال'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
