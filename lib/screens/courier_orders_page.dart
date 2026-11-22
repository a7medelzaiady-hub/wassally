import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order.dart';
import '../services/customer_rating_service.dart';
import '../services/delivery_pin_service.dart';
import '../services/driver_service.dart';
import '../services/order_contact_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/maps.dart';
import '../widgets/customer_rating_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback_fab.dart';
import '../widgets/staff_header.dart';
import '../widgets/order_timer.dart';
import '../utils/dialog_controllers.dart';
import 'quick_courier_orders_page.dart';

/// صورة المحل (من مستند stores لو فيه imageUrl) وإلا أيقونة. بتتخزّن عشان ما نكررش القراءة.
class _StoreAvatar extends StatefulWidget {
  final String storeId;
  final double size;
  const _StoreAvatar({required this.storeId, this.size = 48});

  static final Map<String, String> _cache = {};

  @override
  State<_StoreAvatar> createState() => _StoreAvatarState();
}

class _StoreAvatarState extends State<_StoreAvatar> {
  late final Future<String> _url = _load();

  Future<String> _load() async {
    final id = widget.storeId;
    if (id.isEmpty) return '';
    final cached = _StoreAvatar._cache[id];
    if (cached != null) return cached;
    try {
      final d = await FirebaseFirestore.instance
          .collection('stores')
          .doc(id)
          .get();
      final m = d.data() ?? const <String, dynamic>{};
      var u = (m['imageUrl'] ?? '').toString();
      if (!u.startsWith('http')) u = (m['image'] ?? '').toString();
      if (!u.startsWith('http')) u = '';
      _StoreAvatar._cache[id] = u;
      return u;
    } catch (_) {
      return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = BorderRadius.circular(14);
    Widget fallback() => Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(borderRadius: r, gradient: Brand.softGradient),
      child: Icon(
        Icons.local_mall_outlined,
        color: Brand.gold,
        size: widget.size * 0.45,
      ),
    );
    return FutureBuilder<String>(
      future: _url,
      builder: (context, snap) {
        final u = snap.data ?? '';
        if (u.isEmpty) return fallback();
        return ClipRRect(
          borderRadius: r,
          child: Image.network(
            u,
            width: widget.size,
            height: widget.size,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => fallback(),
          ),
        );
      },
    );
  }
}

/// خانة رقم (مبلغ / عمولة) بخلفية خفيفة.
Widget _moneyBox(String label, String value, Color color) {
  return Expanded(
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: TextStyle(fontSize: 11.5, color: kMuted)),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    ),
  );
}

BoxDecoration _cardDeco() => BoxDecoration(
  color: Colors.white,
  borderRadius: BorderRadius.circular(20),
  border: Border.all(color: kLine),
  boxShadow: const [
    BoxShadow(color: Color(0x0F000000), blurRadius: 14, offset: Offset(0, 5)),
  ],
);

enum _Tab { available, current, history }

/// شاشة المندوب: الطلبات المتاحة، الطلبات الحالية، وسجل التسليمات لتقييم العميل بعد انتهاء الطلب.
class CourierOrdersPage extends StatefulWidget {
  final String name;
  const CourierOrdersPage({super.key, this.name = ''});

  @override
  State<CourierOrdersPage> createState() => _CourierOrdersPageState();
}

class _CourierOrdersPageState extends State<CourierOrdersPage> {
  final String _uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  late final Stream<List<AppOrder>> _orders = StaffOrderService.watchForCourier(
    _uid,
  );
  late final Stream<List<AppOrder>> _available =
      StaffOrderService.watchAvailableOrders();
  late final Future<RatingSummary?> _myRating = RatingService.courier(_uid);
  late final Future<DeliveryStats> _todayStats =
      StaffOrderService.loadCourierStats(_uid, since: startOfToday());
  _Tab _tab = _Tab.available;

  bool _isCurrent(AppOrder o) =>
      o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled;

  Widget _chip(String label, _Tab t) {
    final sel = _tab == t;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _tab = t),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: sel ? Brand.green : Colors.transparent,
            borderRadius: BorderRadius.circular(12),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
            label,
            maxLines: 1,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: sel ? Colors.white : kMuted,
            ),
          ),
          ),
        ),
      ),
    );
  }

  Widget _stat(IconData icon, String label, String value, Color color) =>
      Expanded(
        child: Column(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: color.withValues(alpha: 0.12),
              ),
              child: Icon(icon, color: color, size: 20),
            ),
            const SizedBox(height: 6),
            FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                value,
                maxLines: 1,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 14.5,
                ),
              ),
            ),
            const SizedBox(height: 1),
            Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: kMuted, fontSize: 11),
            ),
          ],
        ),
      );

  Widget _statsCard(int availableToday, DeliveryStats today) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 6),
      decoration: _cardDeco(),
      child: Row(
        children: [
          _stat(
            Icons.inventory_2_outlined,
            'متاحة',
            '$availableToday',
            Brand.green,
          ),
          _stat(
            Icons.check_circle_outline,
            'سلّمتها',
            '${today.delivered}',
            const Color(0xFF3B82F6),
          ),
          _stat(
            Icons.account_balance_wallet_outlined,
            'عمولتي',
            formatPrice(today.earnings),
            Brand.green,
          ),
        ],
      ),
    );
  }

  Widget _error() => const EmptyState(
    icon: Icons.lock_outline,
    title: 'تعذر تحميل الطلبات',
    message: 'تأكد إن حسابك مضاف في couriers وإن القواعد منشورة.',
  );

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: const FeedbackFab(),
      body: Column(
        children: [
          FutureBuilder<RatingSummary?>(
            future: _myRating,
            builder: (context, rs) => StaffHeader(
              title: 'طلبات التوصيل',
              subtitle: [
                widget.name.isEmpty ? 'أهلاً' : 'أهلاً ${widget.name}',
                if (rs.data != null && rs.data!.count > 0)
                  'تقييمك ${rs.data!.avg.toStringAsFixed(1)}',
              ].join(' · '),
            ),
          ),
          // «الطلبات السريعة»: بيظهر للمناديب المعتمدين (quickEnabled) بس.
          const QuickCourierEntry(),
          Expanded(
            child: StreamBuilder<List<AppOrder>>(
              stream: _orders,
              builder: (context, mineSnap) {
                if (mineSnap.hasError) return _error();
                if (!mineSnap.hasData) {
                  return Center(
                    child: CircularProgressIndicator(color: kPrimary),
                  );
                }
                final mine = mineSnap.data!;
                return StreamBuilder<List<AppOrder>>(
                  stream: _available,
                  builder: (context, avSnap) {
                    final available = avSnap.data ?? const <AppOrder>[];
                    final today = startOfToday();
                    final availableToday = available
                        .where(
                          (o) =>
                              o.createdAt == null ||
                              !o.createdAt!.isBefore(today),
                        )
                        .length;
                    final current = mine.where(_isCurrent).toList();
                    final completed = mine
                        .where((o) =>
                            o.status == OrderStatus.delivered ||
                            (o.status == OrderStatus.cancelled &&
                                o.lastDeliveryIssueId.isNotEmpty))
                        .toList();
                    final List<AppOrder> shown = switch (_tab) {
                      _Tab.available => available,
                      _Tab.current => current,
                      _Tab.history => completed,
                    };

                    return Column(
                      children: [
                        FutureBuilder<DeliveryStats>(
                          future: _todayStats,
                          builder: (context, statsSnap) {
                            if (statsSnap.hasError) {
                              return Padding(
                                padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
                                child: Text(
                                  'تعذر تحميل إحصائيات التسليم. اسحب لتحديث الصفحة أو حاول لاحقًا.',
                                  style: TextStyle(color: kMuted, fontSize: 12),
                                ),
                              );
                            }
                            if (!statsSnap.hasData) {
                              return const Padding(
                                padding: EdgeInsets.all(18),
                                child: Center(child: CircularProgressIndicator()),
                              );
                            }
                            return _statsCard(availableToday, statsSnap.data!);
                          },
                        ),
                        Container(
                          margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: kLine),
                          ),
                          child: Row(
                            children: [
                              _chip(
                                'المتاحة (${available.length})',
                                _Tab.available,
                              ),
                              _chip('طلباتي (${current.length})', _Tab.current),
                              _chip('سجل التسليمات (${completed.length})', _Tab.history),
                            ],
                          ),
                        ),
                        if (_tab == _Tab.available && avSnap.hasError)
                          const Padding(
                            padding: EdgeInsets.all(16),
                            child: Text(
                              'تعذر تحميل الطلبات المتاحة. تأكد إن القواعد الجديدة منشورة.',
                            ),
                          ),
                        Expanded(
                          child: shown.isEmpty
                              ? EmptyState(
                                  icon: Icons.two_wheeler,
                                  title: switch (_tab) {
                                    _Tab.available => 'مفيش طلبات متاحة دلوقتي',
                                    _Tab.current => 'مفيش طلبات حالية',
                                    _Tab.history => 'مفيش تسليمات مكتملة',
                                  },
                                  message: switch (_tab) {
                                    _Tab.available => 'أول ما محل يبدأ تجهيز طلب هيظهر هنا. أول مندوب نشط يضغط «استلم الطلب» وينجح في تأكيده يتعيّن له الطلب.',
                                    _Tab.current => 'الطلبات اللي تستلمها هتظهر هنا.',
                                    _Tab.history => 'الطلبات المكتملة هتظهر هنا، وتقدر تقيّم تعامل العميل بعد التسليم.',
                                  },
                                )
                              : ListView.separated(
                                  padding: const EdgeInsets.fromLTRB(
                                    16,
                                    4,
                                    16,
                                    90,
                                  ),
                                  itemCount: shown.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 12),
                                  itemBuilder: (context, i) =>
                                      _tab == _Tab.available
                                      ? _AvailableOrderCard(order: shown[i])
                                      : _CourierOrderCard(order: shown[i]),
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// كارت طلب متاح: بسيط، اسم المحل والمنطقة والعمولة وزر "استلم الطلب".
class _AvailableOrderCard extends StatefulWidget {
  final AppOrder order;
  const _AvailableOrderCard({required this.order});

  @override
  State<_AvailableOrderCard> createState() => _AvailableOrderCardState();
}

class _AvailableOrderCardState extends State<_AvailableOrderCard> {
  bool _busy = false;

  Future<void> _claim() async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.claimOrder(widget.order);
      messenger.showSnackBar(const SnackBar(content: Text('تم استلام الطلب.')));
    } on FirebaseException catch (e) {
      messenger.showSnackBar(SnackBar(
        content: Text(e.code == 'permission-denied'
            ? 'الطلب اتاخد من مندوب تاني.'
            : 'تعذر الاستلام (${e.code}).'),
      ));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('$e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StoreAvatar(storeId: o.storeId),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.storeName.isEmpty ? 'المحل' : o.storeName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w800,
                        color: Brand.ink,
                      ),
                    ),
                    // وجهة مختصرة فقط قبل الاستلام؛ لا نعرض عنوان العميل أو هاتفه.
                    const SizedBox(height: 5),
                    Text(
                      'رايح: ${o.area.trim().isEmpty ? 'المنطقة غير محددة' : o.area.trim()}',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        color: Brand.green,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'طلب #${o.id.length > 8 ? o.id.substring(0, 8) : o.id}',
                      style: TextStyle(fontSize: 11, color: kMuted),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('عمولتك', style: TextStyle(fontSize: 11, color: kMuted)),
                  Text(
                    formatPrice(o.courierFee),
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Brand.green,
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: _busy ? null : _claim,
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                textStyle: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Text('استلم الطلب'),
            ),
          ),
        ],
      ),
    );
  }
}

class _CourierOrderCard extends StatefulWidget {
  final AppOrder order;
  const _CourierOrderCard({required this.order});

  @override
  State<_CourierOrderCard> createState() => _CourierOrderCardState();
}

class _CourierOrderCardState extends State<_CourierOrderCard> {
  bool _busy = false;
  bool _customerRated = false;

  // بيانات العميل (الاسم الكامل والموبايل والعنوان) من المستند الخاص،
  // والقواعد بتسمح بيها للمندوب المكلّف بالطلب وهو لسه جاري.
  OrderContact? _contact;
  bool _contactFailed = false;

  AppOrder get _o => widget.order.withContact(_contact);

  @override
  void initState() {
    super.initState();
    if (widget.order.status != OrderStatus.delivered &&
        widget.order.status != OrderStatus.cancelled) {
      _loadContact();
    }
  }

  @override
  void didUpdateWidget(covariant _CourierOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id ||
        oldWidget.order.status != widget.order.status) {
      _contact = null;
      _contactFailed = false;
      if (widget.order.status != OrderStatus.delivered &&
          widget.order.status != OrderStatus.cancelled) {
        _loadContact();
      }
    }
  }

  Future<void> _loadContact() async {
    if (mounted) {
      setState(() {
        _contactFailed = false;
      });
    }
    try {
      final contact = await OrderContactService.load(widget.order.id);
      if (mounted) setState(() => _contact = contact);
    } catch (error) {
      debugPrint('Courier contact load failed: $error');
      if (mounted) setState(() => _contactFailed = true);
    }
  }

  /// التسليم بقى برمز من 4 أرقام بياخده المندوب من العميل، والـWorker هو اللي بيتحقق.
  Future<void> _deliverWithPin() async {
    final pin = await showDialog<String>(
      context: context,
      builder: (ctx) => const _DeliveryPinDialog(),
    );
    if (pin == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final delivered = await DeliveryPinService.deliver(widget.order.id, pin);
      messenger.showSnackBar(SnackBar(
        content: Text(delivered
            ? 'تم تأكيد التسليم. حصّل ${formatPrice(widget.order.payable)} من العميل.'
            : 'تم تأكيد التسليم. سلّم النقدية للمحل.'),
      ));
    } on DeliveryPinError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _advance() async {
    final next = widget.order.status.courierNext;
    if (next == null || _busy || widget.order.status.courierMustWait) return;
    if (courierPinLocked(widget.order)) return;
    if (next == OrderStatus.onTheWay &&
        kCourierWaitsForReady &&
        !widget.order.ready) {
      return;
    }
    final delivering = next == OrderStatus.delivered;
    if (delivering) {
      await _deliverWithPin();
      return;
    }

    final ok = await confirmDialog(
      context,
      title: 'تأكيد الاستلام',
      message: 'هتبدأ توصيل الطلب؟',
      confirmLabel: 'ابدأ التوصيل',
    );
    if (!ok || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.setStatus(
        widget.order.id,
        next,
        from: widget.order.status,
        actorRole: 'courier',
      );
    } on FirebaseException catch (error) {
      final message = switch (error.code) {
        'permission-denied' =>
          'التحديث غير مسموح. تأكد من تعيين الطلب وجاهزية المحل.',
        'unavailable' =>
          'الاتصال بالإنترنت غير متاح. لم يتم تأكيد التحديث؛ حدّث الطلب قبل إعادة المحاولة.',
        'deadline-exceeded' =>
          'انتهت مهلة الاتصال. تحقق من حالة الطلب قبل المحاولة مرة أخرى.',
        'failed-precondition' =>
          'حالة الطلب لا تسمح بهذه الخطوة. حدّث الصفحة.',
        'not-found' => 'الطلب لم يعد موجودًا.',
        _ => 'تعذر تحديث الطلب (${error.code}). حاول مرة أخرى.',
      };
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } on StateError catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error.message)),
      );
    } catch (error) {
      debugPrint('Courier order status update failed: $error');
      messenger.showSnackBar(
        const SnackBar(content: Text('حدث خطأ غير متوقع أثناء تحديث الطلب.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _handCashToStore() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'تسليم النقدية للمحل',
      message: 'هل سلّمت قيمة الطلب للمحل بالفعل؟',
      confirmLabel: 'تأكيد تسليم النقدية',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await StaffOrderService.recordCashHandedToStore(widget.order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تسجيل تسليم النقدية. في انتظار تأكيد المحل.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is StateError ? error.message : 'تعذر تسجيل تسليم النقدية.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _recordArrival() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.recordCourierArrival(widget.order.id);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تسجيل وصولك للعنوان. حاول التواصل مع العميل.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error is StateError ? error.message : 'تعذر تسجيل الوصول.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _reportDeliveryIssue() async {
    if (_busy || widget.order.courierArrivedAt == null) return;
    const reasons = {
      'no_answer': 'العميل لا يرد',
      'wrong_address': 'العنوان غير صحيح',
      'refused_order': 'رفض الاستلام',
      'no_cash': 'لا يملك قيمة الطلب النقدي',
      'customer_requested_delay': 'طلب تأجيل التسليم',
      'unsafe_location': 'المكان غير آمن',
      'other': 'سبب آخر',
    };
    final note = TextEditingController();
    var reason = 'no_answer';
    var contactAttempted = false;
    final result = await showDialog<({String reason, String note})>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            title: const Text('تعذر تسليم الطلب'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  DropdownButtonFormField<String>(
                    initialValue: reason,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'سبب تعذر التسليم',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      for (final entry in reasons.entries)
                        DropdownMenuItem(
                          value: entry.key,
                          child: Text(entry.value),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) setDialogState(() => reason = value);
                    },
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: note,
                    minLines: 2,
                    maxLines: 4,
                    maxLength: 300,
                    decoration: const InputDecoration(
                      labelText: 'تفاصيل مختصرة (اختياري)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: contactAttempted,
                    onChanged: (value) => setDialogState(
                      () => contactAttempted = value == true,
                    ),
                    title: const Text('حاولت الاتصال أو مراسلة العميل'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                  const Text(
                    'بعد تسجيل السبب تقدر ترجع الطلب للمحل مباشرة، والمحل يؤكد استلامه.',
                    style: TextStyle(fontSize: 11.5, color: Colors.black54),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: contactAttempted
                    ? () => Navigator.pop(
                          dialogContext,
                          (reason: reason, note: note.text.trim()),
                        )
                    : null,
                child: const Text('ابدأ إرجاع الطلب'),
              ),
            ],
          ),
        ),
      ),
    );
    disposeAfterDialogCloses(note);
    if (result == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.reportDeliveryIssue(
        widget.order,
        reason: result.reason,
        note: result.note,
        contactAttempted: true,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تسجيل السبب. ارجع الطلب للمحل ثم سجّل الإرجاع.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error is StateError ? error.message : 'تعذر إرسال بلاغ التسليم.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _activeDeliveryIssuePanel(AppOrder order) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: StaffOrderService.watchDeliveryIssue(order.activeDeliveryIssueId),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Text('تعذر تحميل حالة إرجاع الطلب.');
        }
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Text('جارٍ تحميل حالة إرجاع الطلب.');
        }
        final data = snapshot.data!.data() ?? const <String, dynamic>{};
        final status = (data['status'] ?? 'open').toString();
        final decision = (data['adminDecision'] ?? '').toString();
        if (status == 'retry') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(decision.isEmpty ? 'الإدارة وافقت على إعادة المحاولة.' : decision),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _busy
                    ? null
                    : () async {
                        setState(() => _busy = true);
                        try {
                          await StaffOrderService.resumeDeliveryAfterIssue(
                            orderId: order.id,
                            issueId: order.activeDeliveryIssueId,
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر استئناف التوصيل: $error')),
                          );
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.replay),
                label: const Text('استأنف التوصيل'),
              ),
            ],
          );
        }
        if (status == 'return_to_store') {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(decision.isEmpty ? 'ارجع الطلب للمحل ثم أكد الإرجاع.' : decision),
              const SizedBox(height: 8),
              FilledButton.tonalIcon(
                onPressed: _busy
                    ? null
                    : () async {
                        final ok = await confirmDialog(
                          context,
                          title: 'تأكيد إرجاع الطلب',
                          message: 'هل رجعت الطلب للمحل وسلمته لمسؤول المحل؟',
                          confirmLabel: 'تم الإرجاع',
                        );
                        if (!ok || !mounted) return;
                        setState(() => _busy = true);
                        try {
                          await StaffOrderService.confirmDeliveryReturnedToStore(
                            orderId: order.id,
                            issueId: order.activeDeliveryIssueId,
                          );
                        } catch (error) {
                          if (!context.mounted) return;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(content: Text('تعذر تسجيل الإرجاع: $error')),
                          );
                        } finally {
                          if (mounted) setState(() => _busy = false);
                        }
                      },
                icon: const Icon(Icons.storefront_outlined),
                label: const Text('أكدت إرجاع الطلب للمحل'),
              ),
            ],
          );
        }
        if (status == 'returned_to_store') {
          return const Text(
            'تم تسجيل رجوع الطلب للمحل. الطلب هيتقفل أول ما المحل يأكد استلامه.',
            style: TextStyle(fontWeight: FontWeight.w700),
          );
        }
        return const Text(
          'بلاغ تعذر التسليم قيد مراجعة الإدارة. لا تؤكد التسليم ولا تترك الطلب.',
          style: TextStyle(fontWeight: FontWeight.w700),
        );
      },
    );
  }

  Future<void> _openMap() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await openInMaps(_o.address);
    if (!ok) {
      messenger.showSnackBar(const SnackBar(content: Text('تعذر فتح الخريطة')));
    }
  }

  Future<void> _call() async {
    final uri = Uri.parse('tel:${_o.phone}');
    try {
      await launchUrl(uri);
    } catch (_) {
      await Clipboard.setData(ClipboardData(text: _o.phone));
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('تم نسخ الرقم')));
      }
    }
  }

  Future<void> _rateCustomer() async {
    if (_busy || widget.order.userId.isEmpty) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    var alreadyRated = false;
    try {
      alreadyRated = await CustomerRatingService.hasRated(
        orderId: widget.order.id,
        reviewerRole: 'courier',
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر التحقق من التقييم السابق: $error')),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (alreadyRated) {
      setState(() => _customerRated = true);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تقييم تعامل العميل على هذا الطلب من قبل.')),
      );
      return;
    }

    final input = await showCustomerRatingDialog(context);
    if (input == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await CustomerRatingService.rate(
        orderId: widget.order.id,
        customerId: widget.order.userId,
        storeId: widget.order.storeId,
        reviewerRole: 'courier',
        rating: input.rating,
        reason: input.reason,
        comment: input.comment,
      );
      if (mounted) setState(() => _customerRated = true);
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تسجيل تقييم العميل. شكرًا لمشاركتك.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text(error is StateError ? error.message : 'تعذر تسجيل تقييم العميل.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _round(IconData icon, String tip, VoidCallback onTap) => IconButton(
    tooltip: tip,
    onPressed: onTap,
    icon: Icon(icon, size: 22, color: Brand.green),
    style: IconButton.styleFrom(
      backgroundColor: Brand.green.withValues(alpha: 0.10),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final o = _o;
    final next = o.status.courierNext;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDeco(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _StoreAvatar(storeId: o.storeId, size: 44),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  o.storeName.isEmpty ? 'المحل' : o.storeName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w800,
                    color: Brand.ink,
                  ),
                ),
              ),
              if (o.courierAt != null)
                OrderTimer(start: o.courierAt!, end: o.deliveredAt),
            ],
          ),
          const SizedBox(height: 12),
          if (_contactFailed)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  const Expanded(
                    child: Text(
                      'تعذر تحميل بيانات العميل. تحقق من الاتصال والصلاحيات.',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _loadContact,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      o.userName.isEmpty ? 'العميل' : o.userName,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: Brand.ink,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      o.address,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        height: 1.35,
                        color: kMuted,
                      ),
                    ),
                  ],
                ),
              ),
              if (o.address.isNotEmpty)
                _round(Icons.map_outlined, 'الخريطة', _openMap),
              if (o.phone.isNotEmpty)
                _round(Icons.call_outlined, 'اتصال', _call),
            ],
          ),
          if (o.courierNotes.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                'ملاحظات العميل للمندوب: ${o.courierNotes}',
                style: TextStyle(fontSize: 12.5, color: kMuted),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              _moneyBox('حصّل من العميل', formatPrice(o.payable), Brand.ink),
              const SizedBox(width: 10),
              _moneyBox('عمولتك', formatPrice(o.courierFee), Brand.green),
            ],
          ),
          if (o.status == OrderStatus.onTheWay &&
              o.deliveryMode == 'external' &&
              o.customerConfirmedAt != null) ...[
            const SizedBox(height: 12),
            if (o.cashHandedToStoreAt == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _handCashToStore,
                  icon: const Icon(Icons.payments_outlined),
                  label: const Text('سلّمت النقدية للمحل'),
                ),
              )
            else
              const Text(
                'تم تسجيل تسليم النقدية. في انتظار تأكيد المحل.',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
          ],
          if (o.status == OrderStatus.onTheWay && o.customerConfirmedAt == null) ...[
            const SizedBox(height: 12),
            if (o.customerDeliveryReportedAt != null)
              const Text(
                'تم إبلاغ العميل بالتسليم. في انتظار تأكيده للاستلام.',
                style: TextStyle(fontWeight: FontWeight.w700),
              )
            else if (o.activeDeliveryIssueId.isNotEmpty)
              _activeDeliveryIssuePanel(o)
            else if (o.courierArrivedAt == null)
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _recordArrival,
                  icon: const Icon(Icons.location_on_outlined),
                  label: const Text('وصلت إلى عنوان العميل'),
                ),
              )
            else ...[
              const Text(
                'تم تسجيل وصولك للعميل. سلّمه الطلب وخد منه رمز التسليم (4 أرقام)، أو سجّل تعذر التسليم.',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              if (courierPinLocked(o))
                Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    'الرمز اتقفل بعد محاولات غلط كتير. الإدارة هتراجع الطلب، استنى قرارها.',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: kDanger),
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: (_busy || courierPinLocked(o)) ? null : _advance,
                      style: FilledButton.styleFrom(shape: const StadiumBorder()),
                      child: Text(courierPinLocked(o) ? 'الرمز مقفول' : 'تأكيد التسليم بالرمز'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _reportDeliveryIssue,
                      icon: const Icon(Icons.report_problem_outlined),
                      label: const Text('تعذر التسليم'),
                    ),
                  ),
                ],
              ),
            ],
          ] else if (next == OrderStatus.onTheWay &&
              kCourierWaitsForReady &&
              !o.ready &&
              !o.status.courierMustWait) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kMuted.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'المحل لسه بيجهّز الطلب. زر بدء التوصيل هيظهر أول ما المحل يأكّد إنه جاهز.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (next != null && o.status.courierMustWait) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: kMuted.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Text(
                'استنى المحل يجهّز الطلب، وبعدها زر بدء التوصيل هيظهر.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (showsPickupButton(o)) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton(
                onPressed: _busy ? null : _advance,
                style: FilledButton.styleFrom(
                  shape: const StadiumBorder(),
                  textStyle: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                child: _busy
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('استلمت من المحل، في الطريق'),
              ),
            ),
          ],
          if ((o.status == OrderStatus.delivered ||
                  (o.status == OrderStatus.cancelled && o.lastDeliveryIssueId.isNotEmpty)) &&
              o.userId.isNotEmpty) ...[
            const SizedBox(height: 12),
            if (_customerRated)
              const Text(
                'تم تقييم تعامل العميل على هذا الطلب.',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.green),
              )
            else
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _rateCustomer,
                  icon: const Icon(Icons.star_outline_rounded),
                  label: const Text('تقييم تعامل العميل'),
                ),
              ),
          ],
        ],
      ),
    );
  }
}


/// حوار إدخال رمز التسليم (4 أرقام) من العميل.
class _DeliveryPinDialog extends StatefulWidget {
  const _DeliveryPinDialog();

  @override
  State<_DeliveryPinDialog> createState() => _DeliveryPinDialogState();
}

class _DeliveryPinDialogState extends State<_DeliveryPinDialog> {
  final _ctrl = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _submit() {
    final pin = DeliveryPinService.normalize(_ctrl.text);
    if (pin == null) {
      setState(() => _error = 'اكتب 4 أرقام.');
      return;
    }
    Navigator.pop(context, pin);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: AlertDialog(
        title: const Text('رمز التسليم'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('اطلب من العميل رمز التسليم اللي ظاهر عنده في التطبيق.'),
            const SizedBox(height: 12),
            TextField(
              controller: _ctrl,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 4,
              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩]'))],
              style: const TextStyle(fontSize: 26, letterSpacing: 8, fontWeight: FontWeight.w800),
              decoration: InputDecoration(counterText: '', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('رجوع')),
          FilledButton(onPressed: _submit, child: const Text('تأكيد التسليم')),
        ],
      ),
    );
  }
}


/// رمز التسليم اتقفل بعد محاولات غلط ولسه الإدارة ما قرّرتش: المندوب ما يقدرش يدخل رمز تاني.
bool courierPinLocked(AppOrder o) =>
    o.deliveryPinLockedAt != null && o.customerConfirmedAt == null;

/// زرار «استلمت من المحل، في الطريق» بيظهر بس لما الخطوة الجاية فعلًا هي بدء التوصيل.
/// (كان بيظهر كمان لطلب في الطريق العميل أكّد استلامه ومستني تسوية النقدية مع المحل.)
bool showsPickupButton(AppOrder o) =>
    o.status.courierNext == OrderStatus.onTheWay &&
    !o.status.courierMustWait &&
    (!kCourierWaitsForReady || o.ready);
