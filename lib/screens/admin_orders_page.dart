import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'referral_campaign_page.dart';

import '../models/order.dart';
import 'admin_navigation_page.dart';
import '../services/price_check.dart';
import '../services/catalog_service.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/order_contact_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/order_pages.dart';
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
import '../widgets/app_snack.dart';
import '../services/route_key.dart';
import '../widgets/scroll_memory.dart';

/// شاشة المدير: كل الطلبات، فلترة بالحالة، تغيير الحالة، وتعيين مندوب.
class AdminOrdersPage extends StatefulWidget {
  final String name;
  const AdminOrdersPage({super.key, this.name = ''});

  @override
  State<AdminOrdersPage> createState() => _AdminOrdersPageState();
}

class _AdminOrdersPageState extends State<AdminOrdersPage> {
  static const _pageSize = 100;

  /// أحدث [_pageSize] طلب لحظيًا (مستمع واحد بحد ثابت).
  StreamSubscription<List<AppOrder>>? _liveSub;
  List<AppOrder>? _live;
  Object? _liveError;

  /// طلبات خرجت من الصفحة اللحظية لما طلبات أحدث وصلت (ما تختفيش من القايمة).
  final Map<String, AppOrder> _spill = {};

  /// الصفحات الأقدم: بتتحمّل مرة واحدة بمؤشر بعد آخر طلب ظاهر.
  final List<AppOrder> _older = [];
  bool _loadingOlder = false;
  bool _olderExhausted = false;
  OrderStatus? _filter;

  /// تنبيه مرة واحدة في الجلسة لما المدير يفتح التطبيق وفيه حاجات محتاجة مراجعة.
  static bool _inboxAlertShown = false;

  /// عناوين المحلات (قراءة واحدة محفوظة في الكاش) عشان كارت الطلب يكتب «محل X وعنوانه».
  Map<String, String> _storeAddresses = const {};

  @override
  void initState() {
    super.initState();
    _liveSub = StaffOrderService.watchAll(limit: _pageSize).listen(
      (next) {
        if (!mounted) return;
        setState(() {
          spillDroppedOrders(
            previousLive: _live ?? const [],
            nextLive: next,
            spill: _spill,
          );
          _live = next;
          _liveError = null;
        });
      },
      onError: (Object e) {
        if (mounted) setState(() => _liveError = e);
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _alertInbox());
    _loadStoreAddresses();
  }

  @override
  void dispose() {
    _liveSub?.cancel();
    super.dispose();
  }

  Future<void> _loadStoreAddresses() async {
    try {
      final snap = await CatalogService.get(
        FirebaseFirestore.instance.collection('stores'),
        'admin_store_addresses',
      );
      final map = <String, String>{
        for (final d in snap.docs)
          d.id: (d.data()['address'] ?? d.data()['locationAddress'] ?? '').toString().trim(),
      };
      if (mounted) setState(() => _storeAddresses = map);
    } catch (_) {}
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
            .push(MaterialPageRoute(
              settings: const RouteSettings(name: RouteKey.adminInbox),
              builder: (_) => const AdminInboxPage(),
            )),
      ),
    ));
  }

  List<AppOrder> get _all =>
      mergeOrderPages(_live ?? const [], [..._spill.values, ..._older]);

  /// في طلبات أقدم لسه ما اتحمّلتش؟ قبل أول صفحة أقدم: لو الصفحة اللحظية مليانة.
  bool get _canLoadMore {
    if (_olderExhausted) return false;
    if (_older.isEmpty) return (_live?.length ?? 0) >= _pageSize;
    return true;
  }

  Future<void> _loadMore() async {
    if (_loadingOlder) return;
    final last = oldestTimedOrder(_all);
    if (last == null) return;
    setState(() => _loadingOlder = true);
    try {
      final page = await StaffOrderService.fetchOlderThan(last, limit: _pageSize);
      if (!mounted) return;
      setState(() {
        _older.addAll(page);
        _olderExhausted = page.length < _pageSize;
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnack('تعذر تحميل الطلبات الأقدم. حاول تاني.'),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingOlder = false);
    }
  }

  /// تايل إحصائية: عدد الطلبات بالحالة، وبيشتغل كفلتر لما تضغط عليه.
  /// فلاتر مضغوطة (Chips) بعدد كل حالة بدل الكروت الكبيرة.
  Widget _filters(List<AppOrder> all) {
    Widget chip(String label, int count, bool selected, VoidCallback onTap, {Color? color}) {
      final c = color ?? AppColors.purple;
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: AppSpacing.xs),
        child: ChoiceChip(
          showCheckmark: false,
          selected: selected,
          onSelected: (_) => onTap(),
          selectedColor: c,
          backgroundColor: Colors.white,
          side: BorderSide(color: selected ? c : AppColors.line),
          shape: const StadiumBorder(),
          label: Text.rich(TextSpan(children: [
            TextSpan(text: label),
            TextSpan(
              text: '  $count',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                color: selected ? Colors.white : c,
              ),
            ),
          ])),
          labelStyle: TextStyle(
            fontSize: AppTypography.label,
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : AppColors.inkSoft,
          ),
        ),
      );
    }

    return SizedBox(
      height: 52,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.xs, AppSpacing.page, AppSpacing.xs),
        children: [
          chip('الكل', all.length, _filter == null, () => setState(() => _filter = null)),
          for (final st in OrderStatus.values)
            if (all.any((o) => o.status == st) || _filter == st)
              chip(
                st.label,
                all.where((o) => o.status == st).length,
                _filter == st,
                () => setState(() => _filter = st),
                color: st.color,
              ),
        ],
      ),
    );
  }

  /// اختصارات الإدارة في صف واحد مضغوط بدل كارتين كبار.
  Widget _quickActions() {
    Widget tile(IconData icon, String label, Widget page, Key key) => Expanded(
          child: Material(
            key: key,
            color: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              side: const BorderSide(color: AppColors.line),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute<void>(builder: (_) => page)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                child: Row(children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: AppColors.purpleSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Icon(icon, color: AppColors.purple, size: 20),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: AppTypography.label,
                          fontWeight: FontWeight.w800,
                          color: AppColors.ink,
                        )),
                  ),
                ]),
              ),
            ),
          ),
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.page, AppSpacing.md, AppSpacing.page, 0),
      child: Row(children: [
        tile(Icons.grid_view_rounded, 'أدوات الإدارة', const AdminNavigationPage(),
            const Key('admin-tools-shortcut')),
        const SizedBox(width: AppSpacing.sm),
        tile(Icons.view_carousel_rounded, 'بوسترات الرئيسية', const AdminBannersPage(),
            const Key('admin-banners-shortcut')),
      ]),
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
      body: Builder(
        builder: (context) {
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
            SliverToBoxAdapter(child: _quickActions()),
            const SliverToBoxAdapter(child: AdminStatsCard()),
          ];

          if (_liveError != null && _live == null) {
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
          } else if (_live == null) {
            slivers.add(
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: CircularProgressIndicator(color: Brand.green),
                ),
              ),
            );
          } else {
            final all = _all;
            // التنبيه على الطلبات اللحظية بس (الأقدم مش بتتحدّث، فحالتها ممكن تكون قديمة).
            slivers.add(SliverToBoxAdapter(child: UnansweredOrdersAlert(orders: _live!)));
            final canLoadMore = _canLoadMore;
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
                              key: const Key('admin-orders-load-older'),
                              onPressed: _loadingOlder ? null : _loadMore,
                              child: Text(_loadingOlder ? 'بيحمّل...' : 'عرض طلبات أقدم'),
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
                          storeAddress: _storeAddresses[shown[i].storeId] ?? '',
                          onTap: () => _openManage(shown[i]),
                        ),
                      );
                    }, childCount: count),
                  ),
                ),
              );
            }
          }

          return RememberScroll(
            name: 'admin/orders',
            builder: (context, scroll) => CustomScrollView(
              controller: scroll,
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              slivers: slivers,
            ),
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

/// «محل فواكه وخضروات» بدل «فواكه وخضروات» (من غير تكرار لو الاسم فيه نوع المكان).
String storeTitle(String name) {
  final n = name.trim();
  if (n.isEmpty) return 'محل';
  const kinds = ['محل', 'مطعم', 'صيدلية', 'سوبر', 'ماركت', 'هايبر', 'كافيه', 'مخبز', 'فرن', 'مكتبة', 'معرض'];
  return kinds.any(n.startsWith) ? n : 'محل $n';
}

/// أول جزء من العنوان (الحي غالبًا) لو الطلب قديم ومفيهوش «area».
String _shortPlace(String address) {
  final a = address.trim();
  if (a.isEmpty) return '';
  final first = a.split(RegExp(r'[،,\n]')).first.trim();
  return first.length > 30 ? '${first.substring(0, 30)}…' : first;
}

/// سطر صغير بأيقونة: «من» المحل و«إلى» الوجهة.
class _RouteLine extends StatelessWidget {
  const _RouteLine({required this.icon, required this.color, required this.text, this.strong = false});

  final IconData icon;
  final Color color;
  final String text;
  final bool strong;

  @override
  Widget build(BuildContext context) => Row(children: [
        Icon(icon, size: 15, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: AppTypography.label,
              fontWeight: strong ? FontWeight.w800 : FontWeight.w500,
              color: strong ? AppColors.inkSoft : AppColors.muted,
            ),
          ),
        ),
      ]);
}

class _AdminOrderCard extends StatelessWidget {
  final AppOrder order;
  final String storeAddress;
  final VoidCallback onTap;
  const _AdminOrderCard({required this.order, required this.onTap, this.storeAddress = ''});

  @override
  Widget build(BuildContext context) {
    final color = order.status.color;
    final unassigned = order.courierName.isEmpty;
    final timer = orderTotalTimer(
      createdAt: order.createdAt,
      deliveredAt: order.deliveredAt,
      delivered: order.status == OrderStatus.delivered,
      cancelled: order.status == OrderStatus.cancelled,
    );
    // الوجهة: الحي بس في القايمة، والتفاصيل (الاسم/الموبايل/العنوان) جوه الطلب.
    final destination = order.area.isNotEmpty ? order.area : _shortPlace(order.address);

    // كارت طلب مضغوط زي تطبيقات التوصيل: المحل والمبلغ، العميل والمنطقة،
    // ثم الوقت والحالة والمندوب. الكارت كله بيفتح التفاصيل.
    return Material(
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        side: const BorderSide(color: AppColors.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // شريط لون الحالة على الطرف.
              Container(width: 4, color: color),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              storeTitle(order.storeName),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: AppTypography.body,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Text(
                            formatPrice(order.payable),
                            style: const TextStyle(
                              fontSize: AppTypography.body,
                              fontWeight: FontWeight.w900,
                              color: AppColors.orangeDeep,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.xxs),
                      _RouteLine(
                        icon: Icons.storefront_rounded,
                        color: AppColors.purple,
                        text: storeAddress.isEmpty ? 'عنوان المحل مش متسجل' : storeAddress,
                      ),
                      const SizedBox(height: 2),
                      _RouteLine(
                        icon: Icons.location_on_rounded,
                        color: AppColors.orange,
                        text: destination.isEmpty ? 'الوجهة في التفاصيل' : 'إلى: $destination',
                        strong: true,
                      ),
                      if (order.deliveryPinLockedAt != null &&
                          order.status == OrderStatus.onTheWay &&
                          order.customerConfirmedAt == null) ...[
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'رمز التسليم اتقفل بعد محاولات غلط من المندوب. راجع الطلب وقرر.',
                          style: TextStyle(color: kDanger, fontSize: 12, fontWeight: FontWeight.w700),
                        ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          _StatusChip(status: order.status),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: unassigned ? AppColors.warningSoft : AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Row(mainAxisSize: MainAxisSize.min, children: [
                              Icon(Icons.delivery_dining_rounded, size: 15,
                                  color: unassigned ? AppColors.warning : AppColors.inkSoft),
                              const SizedBox(width: 3),
                              Text(
                                unassigned ? 'بدون مندوب' : order.courierName,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: unassigned ? AppColors.warning : AppColors.inkSoft,
                                ),
                              ),
                            ]),
                          ),
                          ?timer,
                          if (order.createdAt != null)
                            Text(
                              formatDateTime(order.createdAt!),
                              style: const TextStyle(fontSize: 12, color: AppColors.muted),
                            ),
                        ],
                      ),
                    ],
                  ),
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
  String? _storeAddress;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _orderSub;
  bool _acted = false;
  bool _finished = false;
  String? _last;
  String? _err;

  @override
  void initState() {
    super.initState();
    if (widget.order.storeId.isNotEmpty) {
      FirebaseFirestore.instance.collection('stores').doc(widget.order.storeId).get().then((doc) {
        final data = doc.data();
        if (mounted) setState(() => _storeAddress = (data?['address'] ?? data?['locationAddress'] ?? '').toString());
      }).catchError((Object _) {});
    }
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
    if (!adminPrepStepsApply(_o)) return const [];
    return [
      if (!_o.isVerified) 'اعتماد السعر',
      if (_o.status == OrderStatus.newOrder) 'تغيير الحالة',
      if (_o.courierId.isEmpty) 'تعيين مندوب',
    ];
  }

  /// الشيت ما يتقفلش إلا لما كل الخطوات تخلص.
  void _maybeFinish() {
    if (!_acted || _finished || _remaining.isNotEmpty || !mounted) return;
    // بعد خروج الطلب للتوصيل مفيش «تجهيز»، فما نقفلش الشيت برسالة تجهيز مضلّلة.
    if (!adminPrepStepsApply(_o)) return;
    _finished = true;
    final messenger = ScaffoldMessenger.of(context);
    Navigator.of(context).pop();
    messenger.showSnackBar(
      appSnack('تم تجهيز الطلب بالكامل.'),
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
          appSnack('اكتب رقم صحيح بين 0 و 500.'),
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
    if (!adminCanSetStatus(_o, s)) {
      setState(() => _err = 'مش مسموح تغيّر الطلب لـ«${s.label}» من حالته الحالية.');
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
    if (!adminCanApprovePrice(o)) {
      if (o.status == OrderStatus.cancelled) return const SizedBox.shrink();
      return _noteBox(
        color: kMuted,
        icon: Icons.lock_outline_rounded,
        title: 'اعتماد السعر مقفول',
        body: 'الطلب خرج للتوصيل أو العميل استلمه. التحصيل بالإجمالي ${formatPrice(o.payable)}.',
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

  Widget _statusTile(OrderStatus s, bool selected, {bool enabled = true}) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: Material(
      color: selected ? s.color.withValues(alpha: 0.14) : Colors.white,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: (_busy || !enabled) ? null : () => _changeStatus(s),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
                width: 26,
                height: 26,
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
    ),
    );
  }

  Widget _stepRow(String label, bool done) => Expanded(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs, vertical: AppSpacing.sm),
          decoration: BoxDecoration(
            color: done ? AppColors.successSoft : AppColors.surfaceAlt,
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          child: Column(children: [
            Icon(
              done ? Icons.check_circle_rounded : Icons.radio_button_unchecked,
              size: 18,
              color: done ? AppColors.success : AppColors.muted,
            ),
            const SizedBox(height: 2),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                label,
                maxLines: 1,
                style: TextStyle(
                  fontSize: AppTypography.caption,
                  fontWeight: FontWeight.w800,
                  color: done ? AppColors.success : AppColors.inkSoft,
                ),
              ),
            ),
          ]),
        ),
      );

  /// خطوات تجهيز الطلب + آخر رسالة + اللي باقي.
  Widget _stepsCard() {
    final cancelled = _o.status == OrderStatus.cancelled;
    if (!cancelled && !adminPrepStepsApply(_o)) {
      // بعد خروج الطلب للتوصيل: مفيش خطوات تجهيز، بنعرض بس رسالة آخر إجراء/الخطأ.
      if (_err == null && _last == null) return const SizedBox.shrink();
    }
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
          if (cancelled || adminPrepStepsApply(_o)) Text(
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
          else if (adminPrepStepsApply(_o)) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(children: [
              _stepRow('اعتماد السعر', _o.isVerified),
              const SizedBox(width: AppSpacing.xs),
              _stepRow('تغيير الحالة', _o.status != OrderStatus.newOrder),
              const SizedBox(width: AppSpacing.xs),
              _stepRow('تعيين مندوب', _o.courierId.isNotEmpty),
            ]),
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
            color: AppColors.purple,
            borderRadius: BorderRadius.circular(4),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w800,
            color: Brand.ink,
          ),
        ),
      ],
    );
  }

  Future<void> _call(String phone) async {
    final p = phone.trim();
    if (p.isEmpty) return;
    try {
      await launchUrl(Uri(scheme: 'tel', path: p));
    } catch (_) {}
  }

  Widget _routeStop({
    required IconData icon,
    required Color color,
    required String label,
    required String title,
    List<String> lines = const [],
    String phone = '',
  }) =>
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), shape: BoxShape.circle),
            child: Icon(icon, size: 19, color: color),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: AppTypography.caption, fontWeight: FontWeight.w700, color: AppColors.muted)),
                Text(title,
                    style: const TextStyle(
                        fontSize: AppTypography.body, fontWeight: FontWeight.w800, color: AppColors.ink, height: 1.3)),
                for (final line in lines)
                  if (line.trim().isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(line,
                          style: const TextStyle(fontSize: AppTypography.label, color: AppColors.inkSoft, height: 1.4)),
                    ),
              ],
            ),
          ),
          if (phone.trim().isNotEmpty)
            IconButton.filledTonal(
              tooltip: 'اتصال',
              onPressed: () => _call(phone),
              icon: const Icon(Icons.call_rounded, size: 20),
            ),
        ],
      );

  /// من فين لفين: المحل وعنوانه ← وجهة العميل (الحي، وبعده الاسم والموبايل والعنوان).
  Widget _routeCard(AppOrder o) {
    final c = _contact;
    final hasContact = c != null && !c.isEmpty;
    final storeAddress = _storeAddress == null
        ? 'جاري تحميل العنوان...'
        : (_storeAddress!.isEmpty ? 'عنوان المحل مش متسجل' : _storeAddress!);
    final area = o.area.isNotEmpty ? o.area : _shortPlace(hasContact ? c.address : o.address);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _routeStop(
            icon: Icons.storefront_rounded,
            color: AppColors.purple,
            label: 'من',
            title: storeTitle(o.storeName),
            lines: [storeAddress],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 17),
            child: Container(width: 2, height: 16, color: AppColors.line),
          ),
          _routeStop(
            icon: Icons.location_on_rounded,
            color: AppColors.orange,
            label: 'إلى',
            title: area.isEmpty ? (hasContact ? c.name : 'العميل') : area,
            lines: hasContact
                ? [
                    '${c.name} • ${c.phone}',
                    c.address,
                    if (c.courierNotes.isNotEmpty) 'للمندوب: ${c.courierNotes}',
                  ]
                : const ['بيانات العميل بتتحمل...'],
            phone: hasContact ? c.phone : '',
          ),
        ],
      ),
    );
  }

  /// الأصناف بأسعارها والإجمالي في كارت واحد مرتب.
  Widget _itemsCard(AppOrder o) => Container(
        padding: const EdgeInsets.all(AppSpacing.md),
        decoration: BoxDecoration(
          color: AppColors.bg,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(color: AppColors.line),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('الأصناف (${o.items.length})',
                style: const TextStyle(
                    fontSize: AppTypography.label, fontWeight: FontWeight.w800, color: AppColors.muted)),
            const SizedBox(height: AppSpacing.xs),
            for (final line in o.items)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.purpleSoft,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text('${line.qty}×',
                        style: const TextStyle(
                            fontSize: AppTypography.label, fontWeight: FontWeight.w900, color: AppColors.purple)),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      line.options.isEmpty ? line.name : '${line.name} (${line.options.join('، ')})',
                      style: const TextStyle(
                          fontSize: AppTypography.bodySmall, fontWeight: FontWeight.w700, color: AppColors.ink),
                    ),
                  ),
                  Text(formatPrice(line.total),
                      style: const TextStyle(
                          fontSize: AppTypography.label, fontWeight: FontWeight.w700, color: AppColors.inkSoft)),
                ]),
              ),
            if (o.notes.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text('ملاحظات: ${o.notes}',
                  style: const TextStyle(fontSize: AppTypography.label, color: AppColors.muted, height: 1.4)),
            ],
            const Divider(height: AppSpacing.lg),
            Row(children: [
              const Expanded(
                child: Text('الإجمالي • كاش عند الاستلام',
                    style: TextStyle(
                        fontSize: AppTypography.label, fontWeight: FontWeight.w700, color: AppColors.muted)),
              ),
              Text(formatPrice(o.payable),
                  style: const TextStyle(
                      fontSize: AppTypography.titleSmall, fontWeight: FontWeight.w900, color: AppColors.orangeDeep)),
            ]),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final o = _o;

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
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                  color: Brand.ink,
                ),
              ),
              const Spacer(),
              _StatusChip(status: o.status),
            ],
          ),
          _PhaseTimes(order: o),
          const SizedBox(height: AppSpacing.md),
          _routeCard(o),
          const SizedBox(height: AppSpacing.sm),
          _itemsCard(o),
          _stepsCard(),
          _priceCard(),
          if (_o.referralDiscountMinor > 0 &&
              (_o.status == OrderStatus.delivered || _o.status == OrderStatus.cancelled))
            OutlinedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => ReferralReimbursementPage(initialOrderId: _o.id),
              )),
              child: Text(_o.status == OrderStatus.delivered
                  ? 'تسديد خصم النقاط للمحل'
                  : 'استرجاع نقاط الطلب'),
            ),
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
                    SizedBox(
                      width: w,
                      child: _statusTile(
                        s,
                        s == o.status,
                        enabled: s == o.status || adminCanSetStatus(o, s),
                      ),
                    ),
                ],
              );
            },
          ),
          if (adminStatusLocked(o.status) || o.customerConfirmedAt != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                adminStatusLocked(o.status)
                    ? 'الطلب ${o.status.label}، وحالته مقفولة.'
                    : 'العميل أكد استلام الطلب، فالحالة اتقفلت. المتبقي تسوية النقدية وتأكيد المحل.',
                style: TextStyle(color: kMuted, fontSize: 12, height: 1.4),
              ),
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
/// خطوات التجهيز (اعتماد السعر/تغيير الحالة/تعيين مندوب) بتنطبق قبل خروج الطلب للتوصيل بس.
bool adminPrepStepsApply(AppOrder o) =>
    o.status == OrderStatus.newOrder || o.status == OrderStatus.preparing;

/// اعتماد السعر مسموح في نافذة القواعد بس (pricingApprovalWindow): جديد/بيتجهز،
/// قبل إبلاغ التسليم وقبل تأكيد العميل الاستلام.
bool adminCanApprovePrice(AppOrder o) =>
    adminPrepStepsApply(o) &&
    o.customerDeliveryReportedAt == null &&
    o.customerConfirmedAt == null;

/// الإدارة تقدر تغيّر الحالة لـ[s]؟ بتطابق انتقالات الإدارة في firestore.rules (adminMoveOk):
///  • جديد: تجهيز أو إلغاء. • تجهيز: إلغاء، أو في الطريق بعد جاهزية المحل وتعيين مندوب.
///  • في الطريق: «تم التوصيل» بس بعد قفل الرمز ولمندوب المحل، أو إلغاء بعد توثيق رجوع الطلب
///    للمحل (الخدمة بتتحقق منه). مفيش رجوع لخطوة سابقة.
///  • بعد ما العميل يأكد الاستلام: مفيش أي تغيير (الإغلاق لصاحب المحل بعد تسوية النقدية).
bool adminCanSetStatus(AppOrder o, OrderStatus s) {
  if (adminStatusLocked(o.status)) return false;
  switch (o.status) {
    case OrderStatus.newOrder:
      return s == OrderStatus.preparing || s == OrderStatus.cancelled;
    case OrderStatus.preparing:
      return s == OrderStatus.cancelled ||
          (s == OrderStatus.onTheWay && o.ready && o.courierId.isNotEmpty);
    case OrderStatus.onTheWay:
      if (o.customerConfirmedAt != null) return false;
      if (s == OrderStatus.cancelled) return true;
      return s == OrderStatus.delivered &&
          o.deliveryPinLockedAt != null &&
          o.deliveryMode == 'store' &&
          o.courierId.isNotEmpty;
    default:
      return false;
  }
}

bool needsPinDecision(AppOrder o) =>
    o.deliveryPinLockedAt != null &&
    o.status == OrderStatus.onTheWay &&
    o.customerConfirmedAt == null;
