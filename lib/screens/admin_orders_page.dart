import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../services/price_check.dart';
import '../services/order_contact_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../widgets/order_timer.dart';
import '../widgets/admin_stats_card.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/staff_header.dart';
import '../widgets/unanswered_orders_alert.dart';
import 'admin_banners_page.dart';
import '../services/admin_inbox_counts.dart';
import 'admin_inbox_page.dart';
import '../utils/dialog_controllers.dart';

/// شاشة المدير: كل الطلبات، فلترة بالحالة، تغيير الحالة، وتعيين مندوب.
class AdminOrdersPage extends StatefulWidget {
  final String name;
  const AdminOrdersPage({super.key, this.name = ''});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  static const _pageSize = 100;
  int _limit = _pageSize;
  late Stream<List<AppOrder>> _orders = StaffOrderService.watchAll(
    limit: _limit,
  );
  OrderStatus? _filter;

  /// تنبيه مرة واحدة في الجلسة لما المدير يفتح التطبيق وفيه حاجات محتاجة مراجعة.
  static bool _inboxAlertShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _alertInbox());
  }

  Future<void> _alertInbox() async {
    if (_inboxAlertShown) return;
    _inboxAlertShown = true;
    final c = await AdminInboxCounts.load();
    final text = AdminInboxCounts.alertText(c);
    if (!mounted || text == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      duration: const Duration(seconds: 8),
      content: Text(text),
      action: SnackBarAction(
        label: 'افتح',
        onPressed: () => Navigator.of(context)
            .push(MaterialPageRoute(builder: (_) => const AdminInboxPage())),
      ),
    ));
  }

  void _loadMore() {
    setState(() {
      _limit += _pageSize;
      _orders = StaffOrderService.watchAll(limit: _limit);
    });
  }

  /// تايل إحصائية: عدد الطلبات بالحالة، وبيشتغل كفلتر لما تضغط عليه.
  Widget _statTile({
    required String label,
    required int count,
    required IconData icon,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 10),
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
          width: 134,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft,
                    colors: [color, Color.lerp(color, Colors.black, 0.28)!],
                  )
                : null,
            color: selected ? null : Colors.white,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: selected ? Colors.transparent : kLine),
            boxShadow: [
              BoxShadow(
                color: (selected ? color : Colors.black).withValues(
                  alpha: selected ? 0.35 : 0.05,
                ),
                blurRadius: selected ? 14 : 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? Colors.white.withValues(alpha: 0.22)
                          : color.withValues(alpha: 0.12),
                    ),
                    child: Icon(
                      icon,
                      size: 16,
                      color: selected ? Colors.white : color,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    '$count',
                    style: TextStyle(
                      fontSize: 22,
                      height: 1,
                      fontWeight: FontWeight.w800,
                      color: selected ? Colors.white : Brand.ink,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: selected ? Colors.white : kMuted,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _filters(List<AppOrder> all) {
    return SizedBox(
      height: 100,
      child: ListView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
        children: [
          _statTile(
            label: 'كل الطلبات',
            count: all.length,
            icon: Icons.dashboard_rounded,
            color: Brand.green,
            selected: _filter == null,
            onTap: () => setState(() => _filter = null),
          ),
          for (final s in OrderStatus.values)
            _statTile(
              label: s.label,
              count: all.where((o) => o.status == s).length,
              icon: s.icon,
              color: s.color,
              selected: _filter == s,
              onTap: () => setState(() => _filter = s),
            ),
        ],
      ),
    );
  }

  /// كارت الوصول السريع لصفحة التحكم في بوسترات الرئيسية.
  Widget _bannersShortcut() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      child: Material(
        color: Brand.gold.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const AdminBannersPage())),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Brand.gold.withValues(alpha: 0.5)),
            ),
            child: Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Brand.gold,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.view_carousel_rounded,
                    color: Brand.ink,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'بوسترات الرئيسية',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Brand.ink,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'إضافة وترتيب وإخفاء إعلانات الصفحة الرئيسية',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(
                  Icons.chevron_left_rounded,
                  color: Brand.goldDeep,
                  size: 26,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openManage(AppOrder order) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
      ),
      builder: (_) => _ManageSheet(order: order),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      // كل الصفحة (الهيدر + الإحصائيات + الطلبات) بتتحرك مع بعض في سكرول واحد.
      body: StreamBuilder<List<AppOrder>>(
        stream: _orders,
        builder: (context, snapshot) {
          final slivers = <Widget>[
            SliverToBoxAdapter(
              child: StaffHeader(
                isAdmin: true,
                title: 'إدارة الطلبات',
                subtitle: widget.name.isEmpty
                    ? 'حساب المدير'
                    : 'المدير: ${widget.name}',
              ),
            ),
            SliverToBoxAdapter(child: _bannersShortcut()),
            const SliverToBoxAdapter(child: AdminStatsCard()),
          ];

          if (snapshot.hasError) {
            slivers.add(
              const SliverFillRemaining(
                hasScrollBody: false,
                child: EmptyState(
                  icon: Icons.lock_outline,
                  title: 'تعذر تحميل الطلبات',
                  message: 'تأكد إن حسابك مضاف في admins وإن القواعد منشورة.',
                ),
              ),
            );
          } else if (!snapshot.hasData) {
            slivers.add(
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: Brand.green),
                ),
              ),
            );
          } else {
            final all = snapshot.data!;
            slivers.add(SliverToBoxAdapter(child: UnansweredOrdersAlert(orders: all)));
            // لو عدد الطلبات وصل للحد، غالبًا فيه طلبات أقدم لسه ما اتحمّلتش.
            final canLoadMore = all.length >= _limit;
            final shown = _filter == null
                ? all
                : all.where((o) => o.status == _filter).toList();
            slivers.add(SliverToBoxAdapter(child: _filters(all)));
            if (shown.isEmpty) {
              slivers.add(
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'مفيش طلبات هنا',
                    message: 'الطلبات الجديدة هتظهر لحظيًا.',
                  ),
                ),
              );
            } else {
              final count = shown.length + (canLoadMore ? 1 : 0);
              slivers.add(
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate((context, i) {
                      if (i == shown.length) {
                        return Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: _loadMore,
                              child: const Text('عرض طلبات أقدم'),
                            ),
                          ),
                        );
                      }
                      return Padding(
                        padding: EdgeInsets.only(
                          bottom: i == count - 1 ? 0 : 12,
                        ),
                        child: _AdminOrderCard(
                          order: shown[i],
                          onTap: () => _openManage(shown[i]),
                        ),
                      );
                    }, childCount: count),
                  ),
                ),
              );
            }
          }

          return CustomScrollView(
            physics: const BouncingScrollPhysics(
              parent: AlwaysScrollableScrollPhysics(),
            ),
            slivers: slivers,
          );
        },
      ),
    );
  }
}

/// شارة حالة نصية بس (من غير أيقونات).
class _StatusChip extends StatelessWidget {
  final OrderStatus status;
  const _StatusChip({required this.status});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      decoration: BoxDecoration(
        color: status.color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.label,
        maxLines: 1,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: status.color,
        ),
      ),
    );
  }
}

class _AdminOrderCard extends StatelessWidget {
  final AppOrder order;
  final VoidCallback onTap;
  const _AdminOrderCard({required this.order, required this.onTap});

  Widget _info(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$label: ',
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: kMuted,
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 13,
                height: 1.3,
                fontWeight: FontWeight.w600,
                color: Brand.ink,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final color = order.status.color;
    final unassigned = order.courierName.isEmpty;
    final customer = order.displayCustomer.isEmpty
        ? 'عميل'
        : order.displayCustomer;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.10),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 10,
                ),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: AlignmentDirectional.centerStart,
                    end: AlignmentDirectional.centerEnd,
                    colors: [
                      color.withValues(alpha: 0.16),
                      color.withValues(alpha: 0.03),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: order.createdAt == null
                          ? const SizedBox.shrink()
                          : Text(
                              formatDateTime(order.createdAt!),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w600,
                                color: kMuted,
                              ),
                            ),
                    ),
                    if (orderTotalTimer(
                          createdAt: order.createdAt,
                          deliveredAt: order.deliveredAt,
                          delivered: order.status == OrderStatus.delivered,
                          cancelled: order.status == OrderStatus.cancelled,
                        ) !=
                        null) ...[
                      orderTotalTimer(
                        createdAt: order.createdAt,
                        deliveredAt: order.deliveredAt,
                        delivered: order.status == OrderStatus.delivered,
                        cancelled: order.status == OrderStatus.cancelled,
                      )!,
                      const SizedBox(width: 8),
                    ],
                    _StatusChip(status: order.status),
                  ],
                ),
              ),
              if (order.deliveryPinLockedAt != null &&
                  order.status == OrderStatus.onTheWay &&
                  order.customerConfirmedAt == null)
                Container(
                  color: kDanger.withValues(alpha: 0.08),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Text(
                    'رمز التسليم اتقفل بعد محاولات غلط من المندوب. راجع الطلب وقرر.',
                    style: TextStyle(color: kDanger, fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            order.storeName.isEmpty ? 'محل' : order.storeName,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: Brand.ink,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              'الإجمالي',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: kMuted,
                              ),
                            ),
                            Text(
                              formatPrice(order.payable),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: Brand.goldDeep,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    _info('العميل', customer),
                    if (order.area.isNotEmpty) _info('المنطقة', order.area),
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: unassigned
                            ? Brand.gold.withValues(alpha: 0.14)
                            : Brand.green.withValues(alpha: 0.07),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              unassigned
                                  ? 'لم يتم تعيين مندوب'
                                  : 'المندوب: ${order.courierName}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: unassigned ? Brand.goldDeep : Brand.ink,
                              ),
                            ),
                          ),
                          Icon(
                            Icons.chevron_left_rounded,
                            size: 20,
                            color: unassigned ? Brand.goldDeep : kMuted,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManageSheet extends StatefulWidget {
  final AppOrder order;
  const _ManageSheet({required this.order});

  @override
  State<_ManageSheet> createState() => _ManageSheetState();
}

class _ManageSheetState extends State<_ManageSheet> {
  late final Stream<List<Courier>> _couriers =
      StaffOrderService.watchCouriers();
  // مقارنة أسعار الطلب بالكتالوج (قراءة واحدة لمستند المحل).
  late final Future<PriceCheck> _check = StaffOrderService.checkPrices(
    widget.order,
  );
  bool _busy = false;

  // نسخة حيّة من الطلب: الشيت يفضل مفتوح ويتحدّث بعد كل خطوة.
  late AppOrder _o = widget.order;
  OrderContact? _contact;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  bool _acted = false;
  bool _finished = false;
  String? _last;
  String? _err;

  @override
  void initState() {
    super.initState();
    OrderContactService.load(widget.order.id).then((c) {
      if (mounted) setState(() => _contact = c);
    });
    _orderSub = FirebaseFirestore.instance
        .collection('orders')
        .doc(widget.order.id)
        .snapshots()
        .listen((d) {
          final m = d.data();
          if (m == null || !mounted) return;
          setState(() => _o = AppOrder.fromMap(d.id, m));
          _maybeFinish();
        }, onError: (_) {});
  }

  @override
  void dispose() {
    _orderSub?.cancel();
    super.dispose();
  }

  /// الخطوات المتبقية لتجهيز الطلب: اعتماد السعر، تغيير الحالة، تعيين مندوب.
  List<String> get _remaining {
    if (_o.status == OrderStatus.cancelled) return const [];
    return [
      if (!_o.isVerified) 'اعتماد السعر',
      if (_o.status == OrderStatus.newOrder) 'تغيير الحالة',
      if (_o.courierId.isEmpty) 'تعيين مندوب',
    ];
  }

  /// الشيت ما يتقفلش إلا لما كل الخطوات تخلص.
  void _maybeFinish() {
    if (!_acted || _finished || _remaining.isNotEmpty || !mounted) return;
    _finished = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      const SnackBar(content: Text('تم تجهيز الطلب بالكامل.')),
    );
  }

  Future<void> _run(Future<void> Function() action, String okMessage) async {
    setState(() {
      _busy = true;
      _err = null;
    });
    try {
      await action();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _acted = true;
        _last = okMessage;
      });
      _maybeFinish();
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _err = error is StateError
            ? error.message
            : error is FirebaseException
                ? 'تعذر التنفيذ (${error.code}). راجع حالة الطلب والصلاحيات.'
                : 'تعذر التنفيذ. حاول مرة أخرى.';
      });
    }
  }

  /// أي حالة بعد "جديد" (غير الإلغاء) لازم الإجمالي يكون معتمد قبلها.
  bool _needsVerification(OrderStatus s) =>
      s == OrderStatus.preparing ||
      s == OrderStatus.onTheWay ||
      s == OrderStatus.delivered;

  /// بترجّع الإجمالي المعتمد، أو null لو المدير رفض (العملية تتوقف).
  /// - مطابق للكتالوج: بيتعتمد تلقائيًا.
  /// - فيه فرق: بنسأل المدير يعتمد الإجمالي الصحيح حسب الكتالوج.
  /// - مش قادرين نتحقق: بنسأله يعتمد الإجمالي المكتوب في الطلب.
  Future<double?> _resolveVerification() async {
    final o = _o;
    if (o.isVerified) return o.verifiedTotal;

    final check = await _check;
    if (!mounted) return null;
    if (check.status == PriceCheckStatus.match) return check.expectedTotal;

    final mismatch = check.status == PriceCheckStatus.mismatch;
    final ok = await confirmDialog(
      context,
      title: mismatch ? 'فرق في السعر' : 'مقدرش أتحقق من السعر',
      message: mismatch
          ? 'إجمالي الطلب ${formatPrice(o.total)} لكن حسب أسعار الكتالوج '
                'المفروض ${formatPrice(check.expectedTotal)}. '
                'تعتمد ${formatPrice(check.expectedTotal)}؟'
          : 'مش لاقي المحل أو بعض الأصناف في الكتالوج الحالي. '
                'تعتمد الإجمالي المكتوب في الطلب (${formatPrice(o.total)})؟',
      confirmLabel: 'اعتماد',
      destructive: mismatch,
    );
    if (!ok) return null;
    return mismatch ? check.expectedTotal : o.total;
  }

  /// بيسأل الأدمن عن رسوم التوصيل (عمولة المندوب) ثم يطلب تأكيدها.
  /// فاضي = الرسوم الافتراضية للطلب (20). بيرجّع null لو الأدمن لغى أو كتب رقم غلط.
  Future<double?> _askDeliveryFee() async {
    final def = _o.deliveryFee;
    final ctrl = TextEditingController();
    final typed = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رسوم التوصيل'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          decoration: InputDecoration(
            labelText: 'الرسوم بالجنيه',
            hintText: 'سيبه فاضي = ${formatPrice(def)}',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text),
            child: const Text('متابعة'),
          ),
        ],
      ),
    );
    disposeAfterDialogCloses(ctrl);
    if (typed == null || !mounted) return null;

    var t = typed.trim().replaceAll('٫', '.').replaceAll(',', '.');
    const ar = '٠١٢٣٤٥٦٧٨٩';
    for (var i = 0; i < 10; i++) {
      t = t.replaceAll(ar[i], '$i');
    }
    var fee = def;
    if (t.isNotEmpty) {
      final v = double.tryParse(t);
      if (v == null || v < 0 || v > 500) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('اكتب رقم صحيح بين 0 و 500.')),
        );
        return null;
      }
      fee = v;
    }
    final ok = await confirmDialog(
      context,
      title: 'تأكيد رسوم التوصيل',
      message: t.isEmpty
          ? 'ما كتبتش رسوم، فهتتحسب الرسوم الافتراضية ${formatPrice(def)} '
                '(وهي عمولة المندوب). موافق؟'
          : 'رسوم التوصيل ${formatPrice(fee)} (وهي عمولة المندوب). موافق؟',
      confirmLabel: 'موافق',
    );
    return ok ? fee : null;
  }

  Future<void> _changeStatus(OrderStatus s) async {
    if (s == _o.status || _busy) return;
    // طلب ملغي أو اتسلّم: الحالة مقفولة (القواعد كمان بترفض). بنقول بدل ما نفتح حوارات بلا فايدة.
    if (adminStatusLocked(_o.status)) {
      setState(() => _err = 'الطلب ${_o.status.label}، وحالته مش بتتغير.');
      return;
    }
    if (s == OrderStatus.cancelled) {
      final ok = await confirmDialog(
        context,
        title: 'إلغاء الطلب؟',
        message: 'الطلب هيتحول إلى ملغي.',
        confirmLabel: 'إلغاء الطلب',
        destructive: true,
      );
      if (!ok || !mounted) return;
    }

    double? verified;
    double? fee;
    if (_needsVerification(s) && !_o.isVerified) {
      // رسوم التوصيل: الأدمن يكتبها عند الموافقة، ولو سابها فاضية بتفضل الافتراضية (20).
      fee = await _askDeliveryFee();
      if (fee == null || !mounted) return;
      verified = await _resolveVerification();
      if (verified == null || !mounted) return;
      // الإجمالي المعتمد بيتحسب برسوم التوصيل الجديدة.
      verified += fee - _o.deliveryFee;
    }

    await _run(
      () => StaffOrderService.setStatus(
        _o.id,
        s,
        verifiedTotal: verified,
        finalDeliveryFee: fee,
        from: _o.status,
        // التسليم من المدير لطلب ليه مندوب: بنختم باسم المندوب عشان إحصائياته.
        deliveryStamp: s == OrderStatus.delivered && _o.courierId.isNotEmpty
            ? StaffOrderService.deliveryStampFor(
                _o,
                _o.courierId,
                verifiedTotal: verified,
                fee: fee,
              )
            : null,
      ),
      'تم تحديث الحالة: ${s.label}',
    );
  }

  /// اعتماد يدوي من الكارت (من غير تغيير الحالة).
  Future<void> _approve(double total) async {
    if (_busy) return;
    await _run(
      () => StaffOrderService.verifyTotal(_o, total),
      'تم اعتماد الإجمالي: ${formatPrice(total)}',
    );
  }

  Widget _priceCard() {
    final o = _o;
    if (o.isVerified) {
      return _noteBox(
        color: kSuccess,
        icon: Icons.verified_rounded,
        title: 'الإجمالي المعتمد: ${formatPrice(o.verifiedTotal!)}',
        body: (o.verifiedTotal! - o.total).abs() >= 0.01
            ? 'الإجمالي الأصلي في الطلب كان ${formatPrice(o.total)}.'
            : null,
      );
    }
    return FutureBuilder<PriceCheck>(
      future: _check,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return _noteBox(
            color: kMuted,
            icon: Icons.hourglass_top_rounded,
            title: 'بتحقق من الأسعار...',
          );
        }
        final c = snap.data ?? const PriceCheck.unknown();
        switch (c.status) {
          case PriceCheckStatus.match:
            return _noteBox(
              color: kSuccess,
              icon: Icons.check_circle_outline_rounded,
              title: 'الأسعار مطابقة للكتالوج',
              body: 'هتتعتمد تلقائيًا أول ما تغيّر الحالة، أو اعتمدها الآن.',
              action: TextButton(
                onPressed: _busy ? null : () => _approve(c.expectedTotal),
                child: const Text('اعتماد الآن'),
              ),
            );
          case PriceCheckStatus.mismatch:
            final lines = c.issues
                .map(
                  (i) =>
                      '• ${i.name}: ${formatPrice(i.orderPrice)} في الطلب، '
                      '${formatPrice(i.catalogPrice ?? 0)} في الكتالوج',
                )
                .join('\n');
            return _noteBox(
              color: kDanger,
              icon: Icons.warning_amber_rounded,
              title: 'فرق في السعر! الصحيح ${formatPrice(c.expectedTotal)}',
              body: lines.isEmpty
                  ? 'الإجمالي المكتوب (${formatPrice(o.total)}) مش مطابق.'
                  : lines,
              action: TextButton(
                onPressed: _busy ? null : () => _approve(c.expectedTotal),
                child: Text('اعتماد ${formatPrice(c.expectedTotal)}'),
              ),
            );
          case PriceCheckStatus.unknown:
            return _noteBox(
              color: const Color(0xFFE59A00),
              icon: Icons.help_outline_rounded,
              title: 'مقدرش أتحقق من الأسعار',
              body: c.issues.isEmpty
                  ? 'المحل مش موجود في الكتالوج الحالي.'
                  : 'أصناف مش موجودة: ${c.issues.map((i) => i.name).join('، ')}',
              action: TextButton(
                onPressed: _busy ? null : () => _approve(o.total),
                child: Text('اعتماد ${formatPrice(o.total)}'),
              ),
            );
        }
      },
    );
  }

  Widget _noteBox({
    required Color color,
    required IconData icon,
    required String title,
    String? body,
    Widget? action,
  }) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                    color: color,
                  ),
                ),
                if (body != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    body,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.4,
                      fontWeight: FontWeight.w600,
                      color: Brand.ink,
                    ),
                  ),
                ],
                ?action,
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _assign(Courier c) async {
    if (_busy) return;
    await _run(
      () => StaffOrderService.assignCourier(_o.id, c),
      'تم تعيين ${c.name}',
    );
  }

  /// تأكيد إن الطلب جاهز للاستلام (للمحلات اللي ملهاش حساب صاحب محل).
  Future<void> _markReady() async {
    if (_busy) return;
    await _run(
      () => StaffOrderService.markReady(_o.id),
      'تم تأكيد إن الطلب جاهز للاستلام',
    );
  }

  Future<void> _unassign() async {
    if (_busy) return;
    await _run(
      () => StaffOrderService.unassignCourier(_o.id),
      'تم إلغاء التعيين',
    );
  }

  /// تايل حالة في شيت الإدارة: شبكة من عمودين بدل الشرايح المتفاوتة.
  /// رمز التسليم اتقفل بعد محاولات غلط: الإدارة تقرر إن العميل استلم.
  /// مندوب المحل: الطلب يتقفل «تم التوصيل». مندوب خارجي: يفضل لتسوية النقدية مع المحل.
  Widget _pinDecisionCard(AppOrder o) {
    final external = o.deliveryMode == 'external';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kDanger.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kDanger.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'رمز التسليم اتقفل بعد محاولات غلط من المندوب. لو اتأكدت إن العميل استلم الطلب، أكّد التسليم.',
            style: TextStyle(color: kDanger, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          FilledButton.icon(
            onPressed: _busy
                ? null
                : () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'تأكيد التسليم',
                      message: external
                          ? 'هيتسجّل إن العميل استلم، والطلب يفضل لحد ما المحل يأكد استلام النقدية من المندوب.'
                          : 'الطلب هيتقفل «تم التوصيل» باسم المندوب.',
                      confirmLabel: 'تأكيد',
                    );
                    if (!ok || !mounted) return;
                    if (external) {
                      await _run(
                        () => StaffOrderService.adminConfirmLockedExternalDelivery(o.id),
                        'تم تأكيد استلام العميل',
                      );
                    } else {
                      await _changeStatus(OrderStatus.delivered);
                    }
                  },
            icon: const Icon(Icons.verified_outlined),
            label: const Text('العميل استلم: أكّد التسليم'),
          ),
        ],
      ),
    );
  }

  Widget _statusTile(OrderStatus s, bool selected) {
    return Material(
      color: selected ? s.color.withValues(alpha: 0.14) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: _busy ? null : () => _changeStatus(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? s.color : kLine,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: s.color.withValues(alpha: selected ? 0.22 : 0.12),
                ),
                child: Icon(s.icon, size: 17, color: s.color),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    s.label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: Brand.ink,
                    ),
                  ),
                ),
              ),
              if (selected)
                Icon(Icons.check_circle_rounded, size: 18, color: s.color),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepRow(String label, bool done) => Padding(
    padding: const EdgeInsets.only(top: 6),
    child: Row(
      children: [
        Icon(
          done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
          size: 18,
          color: done ? kSuccess : kMuted,
        ),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontSize: 13.5,
            fontWeight: FontWeight.w700,
            color: done ? kSuccess : Brand.ink,
          ),
        ),
      ],
    ),
  );

  /// خطوات تجهيز الطلب + آخر رسالة + اللي باقي.
  Widget _stepsCard() {
    final rem = _remaining;
    final cancelled = _o.status == OrderStatus.cancelled;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kLine),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_err != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _err!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kDanger,
                ),
              ),
            ),
          if (_last != null)
            Padding(
              padding: const EdgeInsets.only(bottom: 4),
              child: Text(
                _last!,
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: kSuccess,
                ),
              ),
            ),
          Text(
            'خطوات تجهيز الطلب',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w800,
              color: kMuted,
            ),
          ),
          if (cancelled)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'الطلب ملغي، مفيش خطوات باقية.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
              ),
            )
          else ...[
            _stepRow('اعتماد السعر', _o.isVerified),
            _stepRow('تغيير الحالة', _o.status != OrderStatus.newOrder),
            _stepRow('تعيين مندوب', _o.courierId.isNotEmpty),
            if (rem.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'باقي: ${rem.join('، ')}',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    color: Brand.goldDeep,
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }

  Widget _section(String title) {
    return Row(
      children: [
        Container(
          width: 4,
          height: 18,
          decoration: BoxDecoration(
            color: Brand.gold,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: Brand.ink,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final summary = o.items.map((e) => '${e.name} × ${e.qty}').join('، ');

    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        10,
        20,
        20 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // مقبض السحب
          Center(
            child: Container(
              width: 44,
              height: 5,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: kLine,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          Row(
            children: [
              Text(
                'تفاصيل الطلب',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
              const Spacer(),
              _StatusChip(status: o.status),
            ],
          ),
          _PhaseTimes(order: o),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Brand.bg,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kLine),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summary,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                    color: Brand.ink,
                  ),
                ),
                if (_contact != null && !_contact!.isEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'العميل: ${_contact!.name}\n'
                    'الهاتف: ${_contact!.phone}\n'
                    'العنوان: ${_contact!.address}'
                    '${_contact!.courierNotes.isEmpty ? '' : '\nللمندوب: ${_contact!.courierNotes}'}',
                    style: TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      fontWeight: FontWeight.w700,
                      color: Brand.ink,
                    ),
                  ),
                ],
                if (o.notes.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Text(
                    'ملاحظات: ${o.notes}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: kMuted,
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text(
                      'الإجمالي (كاش عند الاستلام)',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: kMuted,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      formatPrice(o.payable),
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: Brand.goldDeep,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          _stepsCard(),
          _priceCard(),
          if (needsPinDecision(o)) ...[
            const SizedBox(height: 12),
            _pinDecisionCard(o),
          ],
          const SizedBox(height: 20),
          _section('تغيير الحالة'),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final s in OrderStatus.values)
                    SizedBox(width: w, child: _statusTile(s, s == o.status)),
                ],
              );
            },
          ),
          if (o.status == OrderStatus.preparing && !o.ready) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _busy ? null : _markReady,
                icon: const Icon(Icons.inventory_2_outlined),
                label: const Text('الطلب جاهز للاستلام'),
              ),
            ),
          ] else if (o.status == OrderStatus.preparing && o.ready) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Icon(Icons.check_circle, size: 18, color: kSuccess),
                const SizedBox(width: 6),
                Text(
                  'الطلب جاهز للاستلام',
                  style: TextStyle(
                    fontWeight: FontWeight.w800,
                    color: kSuccess,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 22),
          Row(
            children: [
              Expanded(child: _section('تعيين مندوب')),
              if (o.courierId.isNotEmpty)
                TextButton(
                  onPressed: _busy ? null : _unassign,
                  child: const Text('إلغاء التعيين'),
                ),
            ],
          ),
          const SizedBox(height: 8),
          StreamBuilder<List<Courier>>(
            stream: _couriers,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                return const Text('تعذر تحميل المناديب.');
              }
              if (!snapshot.hasData) {
                return Padding(
                  padding: EdgeInsets.all(12),
                  child: Center(
                    child: CircularProgressIndicator(color: Brand.green),
                  ),
                );
              }
              final couriers = [...snapshot.data!];
              if (couriers.isEmpty) {
                return Text(
                  'مفيش مناديب لسه. أضفهم في collection اسمها couriers من Firebase.',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: kMuted,
                  ),
                );
              }
              return Column(
                children: [
                  for (final c in couriers)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(16),
                          onTap: _busy ? null : () => _assign(c),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: c.id == o.courierId ? Brand.gold : kLine,
                                width: c.id == o.courierId ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  backgroundColor: Brand.green.withValues(
                                    alpha: 0.12,
                                  ),
                                  child: Icon(
                                    Icons.two_wheeler_rounded,
                                    color: Brand.green,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        c.name,
                                        style: TextStyle(
                                          fontSize: 14.5,
                                          fontWeight: FontWeight.w800,
                                          color: Brand.ink,
                                        ),
                                      ),
                                      if (c.phone.isNotEmpty)
                                        Text(
                                          c.phone,
                                          style: TextStyle(
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                            color: kMuted,
                                          ),
                                        ),
                                    ],
                                  ),
                                ),
                                if (c.id == o.courierId)
                                  Icon(
                                    Icons.check_circle_rounded,
                                    color: Brand.green,
                                  ),
                              ],
                            ),
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

/// أوقات مراحل الطلب للأدمن: القبول، التجهيز، الطريق، والإجمالي. بتتحمّل مرة واحدة.
class _PhaseTimes extends StatefulWidget {
  final AppOrder order;
  const _PhaseTimes({required this.order});

  @override
  State<_PhaseTimes> createState() => _PhaseTimesState();
}

class _PhaseTimesState extends State<_PhaseTimes> {
  late final Future<Map<String, DateTime>> _f = _load();

  Future<Map<String, DateTime>> _load() async {
    try {
      final snap = await FirebaseFirestore.instance
          .collection('orders')
          .doc(widget.order.id)
          .collection('statusHistory')
          .get();
      final m = <String, DateTime>{};
      for (final d in snap.docs) {
        final t = d.data()['at'];
        if (t is Timestamp) m[d.id] = t.toDate();
      }
      return m;
    } catch (_) {
      return {};
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    if (o.createdAt == null) return const SizedBox.shrink();
    return FutureBuilder<Map<String, DateTime>>(
      future: _f,
      builder: (context, snap) {
        final h = snap.data ?? const <String, DateTime>{};
        final rows = <(String, Duration)>[];
        final prep = h['preparing'];
        final road = h['on_the_way'];
        final done = h['delivered'] ?? o.deliveredAt;
        if (prep != null) {
          rows.add(('لحد ما المحل بدأ التحضير', prep.difference(o.createdAt!)));
        }
        if (prep != null && o.courierAt != null) {
          rows.add(('لحد استلام المندوب', o.courierAt!.difference(prep)));
        }
        if (road != null && done != null) {
          rows.add(('في الطريق للتسليم', done.difference(road)));
        } else if (road != null && o.status == OrderStatus.onTheWay) {
          rows.add(('في الطريق للتسليم', DateTime.now().difference(road)));
        }
        if (rows.isEmpty) return const SizedBox.shrink();
        return Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kPrimarySoft,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                for (final r in rows)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            r.$1,
                            style: TextStyle(fontSize: 12.5, color: kMuted),
                          ),
                        ),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            formatElapsed(r.$2),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}


/// الطلب الملغي أو اللي اتسلّم: الإدارة ما تغيّرش حالته.
bool adminStatusLocked(OrderStatus status) =>
    status == OrderStatus.cancelled || status == OrderStatus.delivered;


/// طلب في الطريق رمزه اتقفل ولسه ما اتأكدش: محتاج قرار من الإدارة.
bool needsPinDecision(AppOrder o) =>
    o.deliveryPinLockedAt != null &&
    o.status == OrderStatus.onTheWay &&
    o.customerConfirmedAt == null;
