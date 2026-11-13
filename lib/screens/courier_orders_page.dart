import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/order.dart';
import '../services/driver_service.dart';
import '../services/order_contact_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../theme/brand.dart';
import '../utils/format.dart';
import '../utils/maps.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback_fab.dart';
import '../widgets/staff_header.dart';
import '../widgets/order_timer.dart';

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

enum _Tab { available, current }

/// شاشة المندوب: الطلبات المتاحة (كل المناديب تشوفها ويقدّموا عليها والمدير يختار)، وطلباته الحالية،
/// والمسلَّمة بتختفي من القوائم (بتتحسب في الإحصائيات بس)
/// وإحصائياته الشخصية بس (اللي سلّمه هو: deliveredBy == uid).
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
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w700,
              color: sel ? Colors.white : kMuted,
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
                    final List<AppOrder> shown = switch (_tab) {
                      _Tab.available => available,
                      _Tab.current => current,
                    };

                    return Column(
                      children: [
                        _statsCard(
                          availableToday,
                          StaffOrderService.courierStats(
                            mine,
                            _uid,
                            since: today,
                          ),
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
                                  },
                                  message: switch (_tab) {
                                    _Tab.available => 'أول ما محل يجهّز طلب هيظهر هنا، وقدّم عليه. المدير أو صاحب المحل هو اللي بيختار المندوب.',
                                    _Tab.current =>
                                      'الطلبات اللي تستلمها هتظهر هنا.',
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
                    // المناديب المتاحين يشوفوا المنطقة بس. العنوان والموبايل بيظهروا
                    // للمندوب اللي استلم الطلب فقط.
                    if (o.area.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        o.area,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: kMuted),
                      ),
                    ],
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
                      fontWeight: FontWeight.w900,
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

  // بيانات العميل (الاسم الكامل والموبايل والعنوان) من المستند الخاص،
  // والقواعد بتسمح بيها للمندوب المكلّف بالطلب وهو لسه جاري.
  OrderContact? _contact;
  bool _contactFailed = false;

  AppOrder get _o => widget.order.withContact(_contact);

  @override
  void initState() {
    super.initState();
    _loadContact();
  }

  @override
  void didUpdateWidget(covariant _CourierOrderCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.order.id != widget.order.id) {
      _contact = null;
      _contactFailed = false;
      _loadContact();
    }
  }

  Future<void> _loadContact() async {
    try {
      final contact = await OrderContactService.load(widget.order.id);
      if (mounted) setState(() => _contact = contact);
    } catch (_) {
      if (mounted) setState(() => _contactFailed = true);
    }
  }

  Future<void> _advance() async {
    final next = widget.order.status.courierNext;
    if (next == null || _busy || widget.order.status.courierMustWait) return;
    if (next == OrderStatus.onTheWay &&
        kCourierWaitsForReady &&
        !widget.order.ready) {
      return;
    }
    final delivering = next == OrderStatus.delivered;

    final ok = await confirmDialog(
      context,
      title: delivering ? 'تأكيد التسليم' : 'تأكيد الاستلام',
      message: delivering
          ? 'سلّمت الطلب وحصّلت ${formatPrice(widget.order.payable)} من العميل؟'
          : 'هتبدأ توصيل الطلب؟',
      confirmLabel: delivering ? 'تم التسليم' : 'ابدأ التوصيل',
    );
    if (!ok || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      if (delivering) {
        await StaffOrderService.markDelivered(widget.order);
      } else {
        await StaffOrderService.setStatus(
          widget.order.id,
          next,
          from: widget.order.status,
          actorRole: 'courier',
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر تحديث الحالة، جرّب تاني.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
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
            const Padding(
              padding: EdgeInsets.only(bottom: 8),
              child: Text('تعذر تحميل بيانات العميل الخاصة. أعد فتح الشاشة أو تحقق من صلاحيات الطلب.'),
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
          if (next == OrderStatus.onTheWay &&
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
                'المحل لسه بيجهّز الطلب. زر الاستلام هيظهر أول ما المحل يأكّد إنه جاهز.',
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
                'استنى المحل يجهّز الطلب، وبعدها زر الاستلام هيظهر.',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ),
          ] else if (next != null) ...[
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
                    : Text(
                        next == OrderStatus.delivered
                            ? 'تم التسليم'
                            : 'استلمت من المحل، في الطريق',
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
