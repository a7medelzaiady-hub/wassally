import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/order.dart';
import '../models/product_offer.dart';
import '../services/catalog_service.dart';
import '../services/customer_rating_service.dart';
import '../services/driver_service.dart';
import '../services/image_service.dart';
import '../services/navigation.dart' show roleInfoOverride;
import '../services/role_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../widgets/customer_rating_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback_fab.dart';
import '../widgets/staff_header.dart';
import '../widgets/order_timer.dart';
import '../widgets/status_pill.dart';
import '../widgets/unanswered_orders_alert.dart';

typedef _Json = Map<String, dynamic>;

/// سبب الخطأ الحقيقي (عشان لو القواعد مش منشورة نعرف).
String _why(Object e) {
  if (e is FirebaseException) {
    return e.code == 'permission-denied'
        ? 'مفيش صلاحية — لازم الإدارة تنشر القواعد (permission-denied)'
        : e.code;
  }
  return e.toString();
}

/// سطر السعر والعرض في قائمة أصناف صاحب المحل (شارة نص العرض وتاريخ انتهائه بتظهر هنا).
String _priceLine(_Json m, num price, bool available) {
  if (!available) return '${formatPrice(price)} • موقوف';
  final e = m['offerEndsAt'];
  final ends = e is Timestamp ? e.toDate() : null;
  final b = StringBuffer(formatPrice(price));
  if (m['oldPrice'] is num) {
    b.write('  (بدل ${formatPrice(m['oldPrice'] as num)})');
  }
  final text = (m['offerText'] ?? '').toString().trim();
  if (text.isNotEmpty) b.write('  • $text');
  if (ends != null) {
    b.write(
      isOfferExpired(ends, DateTime.now())
          ? '  • العرض منتهي'
          : '  • حتى ${ends.day}/${ends.month}/${ends.year}',
    );
  }
  if (m['bestSeller'] == true) b.write('  • الأكثر مبيعًا');
  return b.toString();
}

/// شاشة صاحب المحل: طلبات محله، أصنافه، وفتح/إغلاق المحل.
/// الصلاحيات الحقيقية في firestore.rules (isStoreOwner)، والشاشة دي بتعرض بس.
/// صاحب المحل ما يشوفش عنوان العميل ولا رقمه في الشاشة (المحل مش محتاجهم).
class StoreOwnerPage extends StatelessWidget {
  final String storeId;
  final String name;
  final bool pendingApproval;
  const StoreOwnerPage({
    super.key,
    required this.storeId,
    this.name = '',
    this.pendingApproval = false,
  });

  @override
  Widget build(BuildContext context) {
    if (pendingApproval) {
      return _PendingStoreSetup(storeId: storeId, name: name);
    }
    return StreamBuilder<List<AppOrder>>(
      stream: StaffOrderService.watchForStore(storeId, limit: 100),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <AppOrder>[];
        return DefaultTabController(
          length: 3,
          child: Scaffold(
            floatingActionButton: const FeedbackFab(),
            body: Column(
              children: [
                StaffHeader(
                  title: 'لوحة المحل',
                  subtitle: name.isEmpty ? 'حساب صاحب المحل' : 'أهلاً $name',
                ),
                _ShopStatusBar(storeId: storeId),
                UnansweredOrdersAlert(orders: orders),
                Material(
                  color: Colors.white,
                  child: TabBar(
                    labelColor: kPrimary,
                    indicatorColor: kPrimary,
                    tabs: [
                      Tab(text: 'الطلبات'),
                      Tab(text: 'الأصناف والعروض'),
                      Tab(text: 'الطلبات الخاصة'),
                    ],
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _OwnerOrdersTab(
                        storeId: storeId,
                        orders: orders,
                        loading: !snapshot.hasData && !snapshot.hasError,
                        error: snapshot.error,
                      ),
                      _OwnerProductsTab(storeId: storeId),
                      _OwnerSpecialRequestsTab(storeId: storeId),
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

// ─────────────────────── تجهيز المحل قبل الموافقة ───────────────────────

class _PendingStoreSetup extends StatefulWidget {
  final String storeId;
  final String name;

  const _PendingStoreSetup({required this.storeId, required this.name});

  @override
  State<_PendingStoreSetup> createState() => _PendingStoreSetupState();
}

class _PendingStoreSetupState extends State<_PendingStoreSetup> {
  bool _uploading = false;
  bool _statusHandled = false;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _requestSub;

  @override
  void initState() {
    super.initState();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _requestSub = FirebaseFirestore.instance
          .collection('role_requests')
          .doc('${uid}_store_owner')
          .snapshots()
          .listen((snapshot) {
            final status = snapshot.data()?['status'];
            if (!_statusHandled && (status == 'approved' || status == 'rejected')) {
              _statusHandled = true;
              RoleService.load().then((info) {
                roleInfoOverride.value = info;
              });
            }
          });
    }
  }

  @override
  void dispose() {
    _requestSub?.cancel();
    super.dispose();
  }

  Future<void> _changeImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final url = await ImageService.pickAndUpload(
        'stores',
        storeId: widget.storeId,
      );
      if (url != null) {
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(widget.storeId)
            .update({
              'image': url,
              'imageUrl': url,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        if (!mounted) return;
        messenger.showSnackBar(
          const SnackBar(content: Text('تم تحديث صورة المحل.')),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تحديث الصورة: ${_why(e)}')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final storeRef = FirebaseFirestore.instance
        .collection('stores')
        .doc(widget.storeId);
    return Scaffold(
      floatingActionButton: const FeedbackFab(),
      body: Column(
        children: [
          StaffHeader(
            title: 'تجهيز المحل',
            subtitle: widget.name.isEmpty ? 'مسودة المحل' : 'أهلاً ${widget.name}',
          ),
          StreamBuilder<DocumentSnapshot<_Json>>(
            stream: storeRef.snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              if (snapshot.hasError) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text('تعذر تحميل بيانات المحل. حاول مرة أخرى.'),
                );
              }
              if (data == null) {
                return const Padding(
                  padding: EdgeInsets.all(16),
                  child: CircularProgressIndicator(),
                );
              }
              final title = (data['name'] ?? 'المحل').toString();
              final category = (data['category'] ?? '').toString();
              final image = (data['imageUrl'] ?? data['image'] ?? '').toString();
              final count = (data['productCount'] as num?)?.toInt() ?? 0;
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 64,
                            height: 64,
                            child: image.isEmpty
                                ? Container(
                                    color: kPrimarySoft,
                                    child: Icon(Icons.store, color: kPrimary),
                                  )
                                : Image.network(
                                    image,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        Container(color: kPrimarySoft),
                                  ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                title,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                ),
                              ),
                              Text(category, style: TextStyle(color: kMuted)),
                              Text(
                                'قيد مراجعة الإدارة • المحل غير ظاهر للعملاء',
                                style: TextStyle(
                                  color: kPrimary,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      onPressed: _uploading ? null : _changeImage,
                      icon: _uploading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined),
                      label: const Text('رفع أو تغيير صورة المحل'),
                    ),
                    Text(
                      'أضف 5 أصناف على الأقل وصورة واضحة. لن يظهر المحل للعملاء إلا بعد موافقة الإدارة.',
                      style: TextStyle(color: kMuted, fontSize: 12),
                    ),
                    Text(
                      'عدد الأصناف المسجل: $count',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              );
            },
          ),
          Expanded(child: _OwnerProductsTab(storeId: widget.storeId)),
        ],
      ),
    );
  }
}

// ───────────────────────── فتح / إغلاق المحل ─────────────────────────

class _ShopStatusBar extends StatefulWidget {
  final String storeId;
  const _ShopStatusBar({required this.storeId});

  @override
  State<_ShopStatusBar> createState() => _ShopStatusBarState();
}

class _ShopStatusBarState extends State<_ShopStatusBar> {
  late final Stream<DocumentSnapshot<_Json>> _stream = FirebaseFirestore
      .instance
      .collection('stores')
      .doc(widget.storeId)
      .snapshots();
  bool _busy = false;
  late final Future<RatingSummary?> _rating = RatingService.store(
    widget.storeId,
  );

  Future<void> _changeImage() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      final url = await ImageService.pickAndUpload(
        'stores',
        storeId: widget.storeId,
      );
      if (url != null) {
        await FirebaseFirestore.instance
            .collection('stores')
            .doc(widget.storeId)
            .update({
              'imageUrl': url,
              'image': url,
              'updatedAt': FieldValue.serverTimestamp(),
            });
        await CatalogService.bump();
        messenger.showSnackBar(
          const SnackBar(content: Text('تم تغيير صورة المحل.')),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تغيير الصورة: ${_why(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteStore() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    final ok = await confirmDialog(
      context,
      title: 'حذف المحل',
      message:
          'حذف المحل وكل أصنافه نهائيًا؟ مش هتقدر ترجّعه (لو هترجع قريب اقفله بدل ما تحذفه).',
      confirmLabel: 'حذف المحل',
      destructive: true,
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final store = FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId);
      while (true) {
        final snap = await store.collection('products').limit(400).get();
        if (snap.docs.isEmpty) break;
        final batch = FirebaseFirestore.instance.batch();
        for (final d in snap.docs) {
          batch.delete(d.reference);
        }
        await batch.commit();
      }
      // حذف المحل وربط حساب المالك في Batch واحدة؛ القواعد تتحقق من
      // ملكية المحل والـ storeId القديم قبل إتمام العمليتين ذريًا.
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw StateError('انتهت جلسة الدخول. سجّل الدخول مرة أخرى.');
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(store);
      batch.delete(FirebaseFirestore.instance.collection('storeOwners').doc(uid));
      await batch.commit();
      await CatalogService.bump();
      messenger.showSnackBar(const SnackBar(content: Text('تم حذف المحل.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر حذف المحل: ${_why(e)}')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _setActive(bool value) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .update({'active': value, 'updatedAt': FieldValue.serverTimestamp()});
      await CatalogService.bump();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر تغيير حالة المحل، جرّب تاني.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<_Json>>(
      stream: _stream,
      builder: (context, snap) {
        final data = snap.data?.data();
        if (snap.hasError || (snap.hasData && data == null)) {
          return Container(
            width: double.infinity,
            color: kDanger.withValues(alpha: 0.1),
            padding: const EdgeInsets.all(12),
            child: const Text(
              'تعذر تحميل بيانات المحل. اتأكد مع الإدارة إن حسابك مربوط بمحل صحيح.',
            ),
          );
        }
        if (data == null) return const SizedBox(height: 56);
        final active = (data['active'] as bool?) ?? true;
        final shopName = (data['name'] ?? 'المحل').toString();
        final shopImage = (data['imageUrl'] ?? data['image'] ?? '').toString();
        return Container(
          color: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          child: Column(
            children: [
              Row(
                children: [
                  GestureDetector(
                    onTap: _changeImage,
                    child: Stack(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: SizedBox(
                            width: 48,
                            height: 48,
                            child: shopImage.isEmpty
                                ? Container(
                                    color: kPrimarySoft,
                                    alignment: Alignment.center,
                                    child: Text(
                                      shopName.isEmpty
                                          ? ''
                                          : shopName.substring(0, 1),
                                      style: TextStyle(
                                        color: kPrimary,
                                        fontSize: 22,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  )
                                : Image.network(
                                    shopImage,
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) =>
                                        Container(color: kPrimarySoft),
                                  ),
                          ),
                        ),
                        PositionedDirectional(
                          bottom: 0,
                          end: 0,
                          child: Container(
                            padding: const EdgeInsets.all(3),
                            decoration: BoxDecoration(
                              color: kPrimary,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.camera_alt,
                              size: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          shopName,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          active
                              ? 'المحل مفتوح ويستقبل طلبات'
                              : 'المحل مقفول أو بانتظار تفعيل الإدارة',
                          style: TextStyle(
                            color: active ? kSuccess : kDanger,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        FutureBuilder<RatingSummary?>(
                          future: _rating,
                          builder: (context, rs) => Text(
                            rs.data == null
                                ? 'تقييم المحل: ...'
                                : 'تقييم المحل: ${rs.data!.text}',
                            style: TextStyle(color: kMuted, fontSize: 12),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: active,
                    onChanged: _busy || !active ? null : _setActive,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _changeImage,
                      icon: _busy
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.photo_camera_outlined, size: 18),
                      label: const Text('تغيير صورة المحل'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: () =>
                          DefaultTabController.of(context).animateTo(1),
                      icon: const Icon(Icons.local_offer_outlined, size: 18),
                      label: const Text('عمل عرض'),
                    ),
                  ),
                ],
              ),
              TextButton.icon(
                onPressed: _busy ? null : _deleteStore,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('حذف المحل'),
                style: TextButton.styleFrom(foregroundColor: kDanger),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── الطلبات ─────────────────────────

class _OwnerOrdersTab extends StatefulWidget {
  final String storeId;
  final List<AppOrder> orders;
  final bool loading;
  final Object? error;
  const _OwnerOrdersTab({
    required this.storeId,
    required this.orders,
    required this.loading,
    required this.error,
  });

  @override
  State<_OwnerOrdersTab> createState() => _OwnerOrdersTabState();
}

class _OwnerOrdersTabState extends State<_OwnerOrdersTab> {
  bool _showCurrent = true;

  bool _isCurrent(AppOrder o) =>
      o.status != OrderStatus.delivered && o.status != OrderStatus.cancelled;

  @override
  Widget build(BuildContext context) {
    if (widget.error != null) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: 'تعذر تحميل الطلبات',
        message: _why(widget.error!),
      );
    }
    if (widget.loading) {
      return Center(child: CircularProgressIndicator(color: kPrimary));
    }
    final all = widget.orders;
    final current = all.where(_isCurrent).toList();
    final past = all.where((o) => !_isCurrent(o)).toList();
    final shown = _showCurrent ? current : past;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: SegmentedButton<bool>(
            segments: [
              ButtonSegment(
                value: true,
                label: Text('الحالية (${current.length})'),
              ),
              ButtonSegment(
                value: false,
                label: Text('السابقة (${past.length})'),
              ),
            ],
            selected: {_showCurrent},
            onSelectionChanged: (v) =>
                setState(() => _showCurrent = v.first),
          ),
        ),
        Expanded(
          child: shown.isEmpty
              ? EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: _showCurrent
                      ? 'مفيش طلبات حالية'
                      : 'مفيش طلبات سابقة',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: shown.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) =>
                      _OwnerOrderCard(order: shown[i]),
                ),
        ),
      ],
    );
  }
}

class _OwnerOrderCard extends StatefulWidget {
  final AppOrder order;
  const _OwnerOrderCard({required this.order});

  @override
  State<_OwnerOrderCard> createState() => _OwnerOrderCardState();
}

class _OwnerOrderCardState extends State<_OwnerOrderCard> {
  bool _busy = false;
  bool _customerRated = false;

  /// الأصناف اللي المحل اختارها «غير متاحة» (محلي لحد ما يضغط «بلّغ العميل»).
  late Set<String> _unavailable = {...widget.order.unavailableItems};

  @override
  void didUpdateWidget(covariant _OwnerOrderCard old) {
    super.didUpdateWidget(old);
    // لو العميل ردّ (العلامة اتشالت) أو الحالة اتغيّرت، نزامن الاختيار مع الطلب.
    if (old.order.unavailableItems.join('|') !=
        widget.order.unavailableItems.join('|')) {
      _unavailable = {...widget.order.unavailableItems};
    }
  }

  bool get _unavailableChanged {
    final saved = widget.order.unavailableItems.toSet();
    return saved.length != _unavailable.length || !saved.containsAll(_unavailable);
  }

  Future<void> _sendUnavailable() async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.setUnavailableItems(widget.order, _unavailable);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            _unavailable.isEmpty
                ? 'تم شيل علامة النقص.'
                : 'تم تبليغ العميل. هيكمّل من غير الأصناف دي أو يلغي.',
          ),
        ),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.message)));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('تعذر تبليغ العميل. جرّب تاني.')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _chooseStoreCourier() async {
    if (_busy || widget.order.courierId.isNotEmpty) return;
    final courier = await showModalBottomSheet<Courier>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: StreamBuilder<List<Courier>>(
          stream: StaffOrderService.watchStoreCouriers(widget.order.storeId),
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('تعذر تحميل مناديب المحل.'),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final couriers = snapshot.data!;
            if (couriers.isEmpty) {
              return const Padding(
                padding: EdgeInsets.all(24),
                child: Text('لا يوجد مندوب نشط مربوط بهذا المحل. اطلب من الإدارة ربط المندوب أولًا.'),
              );
            }
            return ListView(
              shrinkWrap: true,
              children: [
                const Padding(
                  padding: EdgeInsets.fromLTRB(20, 18, 20, 10),
                  child: Text('اختيار مندوب تابع للمحل', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                ),
                for (final courier in couriers)
                  ListTile(
                    leading: const CircleAvatar(child: Icon(Icons.delivery_dining)),
                    title: Text(courier.name),
                    subtitle: Text(courier.phone.isEmpty ? 'مندوب مسجل في وصلي' : courier.phone),
                    onTap: () => Navigator.of(sheetContext).pop(courier),
                  ),
              ],
            );
          },
        ),
      ),
    );
    if (courier == null || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.assignCourier(widget.order.id, courier);
      messenger.showSnackBar(SnackBar(content: Text('تم تعيين ' + courier.name + ' كمندوب للمحل.')));
    } catch (error) {
      messenger.showSnackBar(SnackBar(content: Text(error is StateError ? error.message : 'تعذر تعيين المندوب.')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _markReady() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'الطلب جاهز؟',
      message: 'هتأكّد إن الطلب جاهز للاستلام. المندوب هيقدر ياخده والعميل هيتبلّغ.',
      confirmLabel: 'جاهز للاستلام',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.markReady(widget.order.id);
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذر تأكيد جاهزية الطلب. ممكن حالته اتغيّرت، جرّب تاني.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _confirmStoreReturn(String issueId) async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'تأكيد استلام المرتجع',
      message: 'هل استلم المحل الطلب المرتجع فعليًا من المندوب؟',
      confirmLabel: 'تأكيد الاستلام',
    );
    if (!ok || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.confirmStoreReceivedReturn(
        orderId: widget.order.id,
        issueId: issueId,
      );
      messenger.showSnackBar(
        const SnackBar(content: Text('تم تأكيد استلام المحل للمرتجع.')),
      );
    } catch (error) {
      messenger.showSnackBar(
        SnackBar(content: Text('تعذر تأكيد الاستلام: $error')),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _returnedIssuePanel(AppOrder order) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: StaffOrderService.watchDeliveryIssue(order.activeDeliveryIssueId),
      builder: (context, snapshot) {
        if (!snapshot.hasData || !snapshot.data!.exists) {
          return const Text('يوجد بلاغ تعذر تسليم مرتبط بهذا الطلب.');
        }
        final status = (snapshot.data!.data()?['status'] ?? '').toString();
        if (status == 'returned_to_store') {
          return SizedBox(
            width: double.infinity,
            child: FilledButton.tonalIcon(
              onPressed: _busy
                  ? null
                  : () => _confirmStoreReturn(order.activeDeliveryIssueId),
              icon: const Icon(Icons.inventory_2_outlined),
              label: const Text('استلمت المرتجع من المندوب'),
            ),
          );
        }
        if (status == 'store_confirmed_return') {
          return const Text(
            'تم تأكيد استلام المحل للمرتجع، والإدارة تقدر تغلق الطلب.',
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
          );
        }
        if (status == 'return_to_store') {
          return const Text(
            'الإدارة طلبت من المندوب إرجاع الطلب للمحل.',
            style: TextStyle(fontSize: 12),
          );
        }
        return const Text(
          'يوجد بلاغ تعذر تسليم، والإدارة تراجعه حاليًا.',
          style: TextStyle(fontSize: 12),
        );
      },
    );
  }

  Future<void> _confirmCashReceived() async {
    if (_busy) return;
    final ok = await confirmDialog(
      context,
      title: 'تأكيد استلام النقدية',
      message: 'أكدت استلام قيمة الطلب من المندوب الخارجي؟ بعد التأكيد سيتم إغلاق الطلب.',
      confirmLabel: 'تأكيد الاستلام وإغلاق الطلب',
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      await StaffOrderService.confirmCashReceived(widget.order);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم تأكيد استلام النقدية وإغلاق الطلب.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(error is StateError ? error.message : 'تعذر تأكيد استلام النقدية.')),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
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
        reviewerRole: 'store_owner',
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
        reviewerRole: 'store_owner',
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

  Future<void> _move(OrderStatus to) async {
    if (_busy) return;
    final accept = to == OrderStatus.preparing;
    final ok = await confirmDialog(
      context,
      title: accept ? 'بدء التجهيز' : 'رفض الطلب',
      message: accept
          ? 'هتبدأ تجهّز الطلب ده؟ العميل هيتبلّغ.'
          : 'رفض الطلب ده؟ هيتلغي والعميل هيتبلّغ.',
      confirmLabel: accept ? 'ابدأ التجهيز' : 'ارفض الطلب',
      destructive: !accept,
    );
    if (!ok || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await StaffOrderService.setStatus(
        widget.order.id,
        to,
        from: widget.order.status,
        actorRole: 'storeOwner',
      );
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('تعذر تحديث الطلب. ممكن حالته اتغيّرت، جرّب تاني.'),
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final o = widget.order;
    final isNew = o.status == OrderStatus.newOrder;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: const [
          BoxShadow(
            color: Color(0x0F000000),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                (o.displayCustomer.isEmpty ? 'عميل' : o.displayCustomer),
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
              ),
              const Spacer(),
              if (orderTotalTimer(
                    createdAt: o.createdAt,
                    deliveredAt: o.deliveredAt,
                    delivered: o.status == OrderStatus.delivered,
                    cancelled: o.status == OrderStatus.cancelled,
                  ) !=
                  null) ...[
                orderTotalTimer(
                  createdAt: o.createdAt,
                  deliveredAt: o.deliveredAt,
                  delivered: o.status == OrderStatus.delivered,
                  cancelled: o.status == OrderStatus.cancelled,
                )!,
                const SizedBox(width: 8),
              ],
              OrderStatusPill(status: o.status),
            ],
          ),
          if (o.createdAt != null) ...[
            const SizedBox(height: 4),
            Text(
              formatDateTime(o.createdAt!),
              style: text.bodySmall?.copyWith(color: kMuted),
            ),
          ],
          const Divider(height: 22),
          for (final line in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${line.name} × ${line.qty}',
                      style: _unavailable.contains(line.name)
                          ? TextStyle(
                              color: kDanger,
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                  ),
                  Text(formatPrice(line.total)),
                  if (isNew)
                    IconButton(
                      tooltip: _unavailable.contains(line.name)
                          ? 'الصنف متاح'
                          : 'صنف غير متاح',
                      visualDensity: VisualDensity.compact,
                      onPressed: _busy
                          ? null
                          : () => setState(() {
                              if (!_unavailable.remove(line.name)) {
                                _unavailable.add(line.name);
                              }
                            }),
                      icon: Icon(
                        _unavailable.contains(line.name)
                            ? Icons.remove_circle
                            : Icons.remove_circle_outline,
                        size: 20,
                        color: kDanger,
                      ),
                    ),
                ],
              ),
            ),
          if (o.notes.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('ملاحظات العميل: ${o.notes}'),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                'إجمالي الأصناف:',
                style: text.bodyMedium?.copyWith(color: kMuted),
              ),
              const SizedBox(width: 6),
              Text(
                formatPrice(o.subtotal),
                style: text.titleMedium?.copyWith(
                  color: kPrimary,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
          if (isNew && _unavailableChanged) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _sendUnavailable,
                style: FilledButton.styleFrom(backgroundColor: kDanger),
                icon: const Icon(Icons.campaign_outlined),
                label: Text(
                  _unavailable.isEmpty ? 'شيل علامة النقص' : 'بلّغ العميل بالصنف الناقص',
                ),
              ),
            ),
          ] else if (isNew && o.hasUnavailableItems) ...[
            const SizedBox(height: 10),
            Text(
              'في انتظار رد العميل على الأصناف الناقصة. لو ماردّش تقدر ترفض الطلب.',
              style: text.bodySmall?.copyWith(
                color: kDanger,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
          if (isNew) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _busy || o.hasUnavailableItems || _unavailable.isNotEmpty
                        ? null
                        : () => _move(OrderStatus.preparing),
                    icon: const Icon(Icons.soup_kitchen),
                    label: const Text('ابدأ التجهيز'),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: _busy ? null : () => _move(OrderStatus.cancelled),
                  style: OutlinedButton.styleFrom(foregroundColor: kDanger),
                  child: const Text('رفض'),
                ),
              ],
            ),
          ] else if (o.status == OrderStatus.preparing) ...[
            const SizedBox(height: 10),
            Text(
              o.courierName.isEmpty
                  ? (o.ready
                      ? 'الطلب متاح لمندوب خارجي.'
                      : 'جاري التجهيز. اختار مندوب المحل أو أتح الطلب لمندوب خارجي.')
                  : 'المندوب: ${o.courierName}',
              style: text.bodySmall?.copyWith(color: kMuted),
            ),
            if (o.courierId.isEmpty) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _busy ? null : _chooseStoreCourier,
                  icon: const Icon(Icons.storefront_outlined),
                  label: const Text('اختيار مندوب تابع للمحل'),
                ),
              ),
            ],
            const SizedBox(height: 10),
            if (o.ready)
              Row(
                children: [
                  Icon(Icons.check_circle, size: 18, color: kSuccess),
                  const SizedBox(width: 6),
                  Text(
                    'الطلب جاهز للاستلام',
                    style: text.bodyMedium?.copyWith(
                      color: kSuccess,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _markReady,
                  icon: const Icon(Icons.inventory_2_outlined),
                  label: Text(o.courierId.isEmpty ? 'جاهز — إتاحة لمندوب خارجي' : 'الطلب جاهز للاستلام'),
                ),
              ),
          ],
          if (o.activeDeliveryIssueId.isNotEmpty) ...[
            const SizedBox(height: 12),
            _returnedIssuePanel(o),
          ],
          if (o.status == OrderStatus.onTheWay &&
              o.customerDeliveryReportedAt != null &&
              o.customerConfirmedAt == null) ...[
            const SizedBox(height: 10),
            const Text(
              'المندوب أبلغ بتسليم الطلب، وفي انتظار تأكيد العميل للاستلام.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
          if (o.status == OrderStatus.onTheWay && o.deliveryMode == 'external' &&
              o.customerConfirmedAt != null && o.cashHandedToStoreAt != null) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _busy ? null : _confirmCashReceived,
                icon: const Icon(Icons.payments_outlined),
                label: const Text('تأكيد استلام النقدية من المندوب'),
              ),
            ),
          ] else if (o.status == OrderStatus.onTheWay &&
              o.deliveryMode == 'external' && o.customerConfirmedAt != null) ...[
            const SizedBox(height: 10),
            const Text(
              'العميل أكد الاستلام. في انتظار المندوب لتسليم النقدية للمحل.',
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
          if (o.status == OrderStatus.delivered && o.userId.isNotEmpty) ...[
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

// ───────────────────────── الأصناف ─────────────────────────

class _OwnerProductsTab extends StatefulWidget {
  final String storeId;
  const _OwnerProductsTab({required this.storeId});

  @override
  State<_OwnerProductsTab> createState() => _OwnerProductsTabState();
}

class _OwnerProductsTabState extends State<_OwnerProductsTab> {
  static const _limit = 200;
  final _search = TextEditingController();
  List<QueryDocumentSnapshot<_Json>> _docs = [];
  bool _loading = true;
  bool _error = false;
  String _term = '';

  DocumentReference<_Json> get _storeRef =>
      FirebaseFirestore.instance.collection('stores').doc(widget.storeId);

  CollectionReference<_Json> get _col => _storeRef.collection('products');

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final snap = await _col
          .orderBy('name')
          .limit(_limit)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      setState(() {
        _docs = snap.docs;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _error = true;
        _loading = false;
      });
    }
  }

  /// بيضبط عدد الأصناف المخزّن في المحل (للعرض عند المدير).
  Future<void> _syncCount() async {
    final snap = await _col.count().get();
    await _storeRef.update({
      'productCount': snap.count ?? 0,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// ملخص العروض والأكثر مبيعًا على مستند المحل (الرئيسية بتقراه من هنا).
  Future<void> _syncHighlights() async {
    try {
      Map<String, dynamic> item(_Json m) => {
        'name': (m['name'] ?? '').toString(),
        'price': (m['price'] as num?) ?? 0,
        if (m['oldPrice'] is num) 'oldPrice': m['oldPrice'],
        if ((m['offerText'] ?? '').toString().trim().isNotEmpty)
          'offerText': (m['offerText'] ?? '').toString().trim(),
        if (m['offerEndsAt'] is Timestamp) 'offerEndsAt': m['offerEndsAt'],
        'image': (m['image'] ?? '').toString(),
      };
      bool on(_Json m) => m['available'] != false && m['isAvailable'] != false;
      final offers = <Map<String, dynamic>>[];
      final best = <Map<String, dynamic>>[];
      for (final d in _docs) {
        final m = d.data();
        if (!on(m)) continue;
        final p = (m['price'] as num?) ?? 0;
        final o = m['oldPrice'];
        final e = m['offerEndsAt'];
        final expired = isOfferExpired(
          e is Timestamp ? e.toDate() : null,
          DateTime.now(),
        );
        final offerText = (m['offerText'] ?? '').toString().trim();
        final hasPriceDiscount = o is num && o > p;
        if ((hasPriceDiscount || offerText.isNotEmpty) &&
            !expired &&
            offers.length < 12) {
          offers.add(item(m));
        }
        if (m['bestSeller'] == true && best.length < 12) best.add(item(m));
      }
      await _storeRef.update({
        'offerItems': offers,
        'bestItems': best,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await CatalogService.bump();
    } catch (_) {}
  }

  Future<void> _edit(QueryDocumentSnapshot<_Json>? doc) async {
    final result = await showDialog<_ProductForm>(
      context: context,
      builder: (_) =>
          _ProductDialog(existing: doc?.data(), storeId: widget.storeId),
    );
    if (result == null || !mounted) return;

    try {
      if (doc == null) {
        await _col.doc().set({
          'name': result.name,
          'price': result.price,
          'image': result.image,
          if (result.oldPrice != null) 'oldPrice': result.oldPrice,
          if (result.bestSeller) 'bestSeller': true,
          'isAvailable': true,
          'available': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        await _syncCount();
      } else {
        await doc.reference.update({
          'name': result.name,
          'price': result.price,
          'image': result.image,
          'oldPrice': result.oldPrice ?? FieldValue.delete(),
          'bestSeller': result.bestSeller,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      await CatalogService.bump();
      await _load();
      await _syncHighlights();
      _say('تم حفظ الصنف.');
    } catch (e) {
      _say('تعذر حفظ الصنف: ${_why(e)}');
    }
  }

  /// اختيار صنف من القايمة ثم عمل عرض عليه.
  Future<void> _pickForOffer() async {
    if (_docs.isEmpty) {
      _say('ضيف أصناف الأول عشان تعمل عليها عرض.');
      return;
    }
    final picked = await showModalBottomSheet<QueryDocumentSnapshot<_Json>>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.of(ctx).size.height * 0.75,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.all(16),
                  child: Text(
                    'اختار الصنف اللي عايز تعمله عرض',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final d in _docs)
                        ListTile(
                          title: Text((d.data()['name'] ?? '').toString()),
                          subtitle: Text(
                            formatPrice((d.data()['price'] as num?) ?? 0),
                          ),
                          trailing: d.data()['oldPrice'] is num
                              ? Icon(Icons.local_offer, color: kDanger)
                              : null,
                          onTap: () => Navigator.pop(ctx, d),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (picked != null && mounted) await _offer(picked);
  }

  /// عرض سريع: اختار نسبة خصم والسعر الجديد بيتحسب لوحده (والسعر الأصلي بيتحفظ مشطوب).
  Future<void> _offer(QueryDocumentSnapshot<_Json> doc) async {
    final m = doc.data();
    final price = (m['price'] as num?)?.toDouble() ?? 0;
    final old = (m['oldPrice'] as num?)?.toDouble();
    final hasPriceOffer = old != null && old > price;
    final hasOffer =
        hasPriceOffer || (m['offerText'] ?? '').toString().trim().isNotEmpty;
    // السعر الأصلي (قبل أي خصم): بيتحفظ تلقائيًا ويرجع لما العرض يتلغي.
    final base = hasPriceOffer ? old : price;
    final ends = m['offerEndsAt'];

    final choice = await showDialog<_OfferChoice>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: _OfferDialog(
          name: (m['name'] ?? '').toString(),
          base: base,
          hasOffer: hasOffer,
          initialEndsAt: ends is Timestamp ? ends.toDate() : null,
        ),
      ),
    );
    if (choice == null) return;
    try {
      final endsField = choice.endsAt == null
          ? FieldValue.delete()
          : Timestamp.fromDate(choice.endsAt!);
      final Map<String, dynamic> update;
      if (choice.cancel) {
        update = {
          'price': base,
          'oldPrice': FieldValue.delete(),
          'offerText': FieldValue.delete(),
          'offerEndsAt': FieldValue.delete(),
        };
      } else if (choice.mode == _OfferMode.text) {
        update = {
          'price': base,
          'oldPrice': FieldValue.delete(),
          'offerText': choice.text,
          'offerEndsAt': endsField,
        };
      } else {
        update = {
          'price': choice.offerPrice,
          'oldPrice': base,
          'offerText': FieldValue.delete(),
          'offerEndsAt': endsField,
        };
      }
      update['updatedAt'] = FieldValue.serverTimestamp();
      await doc.reference.update(update);
      await CatalogService.bump();
      await _load();
      await _syncHighlights();
      _say(choice.cancel ? 'اتلغى العرض.' : 'تم تفعيل العرض.');
    } catch (e) {
      _say('تعذر تفعيل العرض: ${_why(e)}');
    }
  }

  Future<void> _toggle(QueryDocumentSnapshot<_Json> doc, bool value) async {
    try {
      await doc.reference.update({
        'available': value,
        'isAvailable': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await CatalogService.bump();
      await _load();
      await _syncHighlights();
    } catch (_) {
      _say('تعذر تغيير حالة الصنف.');
    }
  }

  Future<void> _delete(QueryDocumentSnapshot<_Json> doc) async {
    final ok = await confirmDialog(
      context,
      title: 'حذف صنف',
      message:
          'حذف "${doc.data()['name'] ?? ''}" نهائيًا؟ (الإيقاف أنسب لو هيرجع تاني)',
      confirmLabel: 'حذف',
      destructive: true,
    );
    if (!ok || !mounted) return;
    try {
      await doc.reference.delete();
      await _syncCount();
      await CatalogService.bump();
      await _load();
      await _syncHighlights();
      _say('تم حذف الصنف.');
    } catch (_) {
      _say('تعذر حذف الصنف.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final term = _term.trim().toLowerCase();
    final shown = term.isEmpty
        ? _docs
        : _docs
              .where(
                (d) => (d.data()['name'] ?? '')
                    .toString()
                    .toLowerCase()
                    .contains(term),
              )
              .toList();

    Widget body;
    if (_loading) {
      body = Center(child: CircularProgressIndicator(color: kPrimary));
    } else if (_error) {
      body = EmptyState(
        icon: Icons.cloud_off,
        title: 'تعذر تحميل الأصناف',
        message: 'تأكد من الاتصال وحاول تاني.',
        actionLabel: 'إعادة المحاولة',
        onAction: _load,
      );
    } else if (shown.isEmpty) {
      body = EmptyState(
        icon: Icons.inventory_2_outlined,
        title: term.isEmpty ? 'لسه مفيش أصناف' : 'مفيش نتائج',
        message: term.isEmpty ? 'اضغط "إضافة صنف" عشان تبدأ.' : null,
      );
    } else {
      body = ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 90),
        itemCount: shown.length,
        itemBuilder: (context, i) {
          final d = shown[i];
          final m = d.data();
          final available =
              m['available'] != false && m['isAvailable'] != false;
          final image = (m['image'] ?? '').toString();
          final price = (m['price'] as num?) ?? 0;
          return Card(
            child: ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 48,
                  height: 48,
                  child: image.isEmpty
                      ? Icon(Icons.image_outlined, color: kMuted)
                      : Image.network(
                          image,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) =>
                              const Icon(Icons.broken_image_outlined),
                        ),
                ),
              ),
              title: Text(
                (m['name'] ?? '').toString(),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: Text(_priceLine(m, price, available)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'عمل عرض',
                    icon: Icon(Icons.local_offer_outlined, color: kPrimary),
                    onPressed: () => _offer(d),
                  ),
                  Switch(value: available, onChanged: (v) => _toggle(d, v)),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _edit(d);
                      if (v == 'offer') _offer(d);
                      if (v == 'delete') _delete(d);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'offer',
                        child: Text('عمل عرض / خصم'),
                      ),
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'delete', child: Text('حذف')),
                    ],
                  ),
                ],
              ),
            ),
          );
        },
      );
    }

    return Stack(
      children: [
        Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: TextField(
                controller: _search,
                onChanged: (v) => setState(() => _term = v),
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: 'ابحث في الأصناف',
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _pickForOffer,
                  icon: const Icon(Icons.local_offer_outlined),
                  label: const Text('عمل عرض / خصم على صنف'),
                ),
              ),
            ),
            Expanded(child: body),
          ],
        ),
        PositionedDirectional(
          end: 16,
          bottom: 16,
          child: FloatingActionButton.extended(
            onPressed: () => _edit(null),
            icon: const Icon(Icons.add),
            label: const Text('إضافة صنف'),
          ),
        ),
      ],
    );
  }
}

class _ProductForm {
  final String name;
  final double price;
  final String image;
  final double? oldPrice;
  final bool bestSeller;
  const _ProductForm(
    this.name,
    this.price,
    this.image, {
    this.oldPrice,
    this.bestSeller = false,
  });
}

class _ProductDialog extends StatefulWidget {
  final _Json? existing;
  final String storeId;
  const _ProductDialog({this.existing, required this.storeId});

  @override
  State<_ProductDialog> createState() => _ProductDialogState();
}

class _ProductDialogState extends State<_ProductDialog> {
  late final TextEditingController _name = TextEditingController(
    text: (widget.existing?['name'] ?? '').toString(),
  );
  late final TextEditingController _price = TextEditingController(
    text: widget.existing?['price'] == null
        ? ''
        : (widget.existing!['price'] as num).toString(),
  );
  late final TextEditingController _old = TextEditingController(
    text: widget.existing?['oldPrice'] is num
        ? (widget.existing!['oldPrice'] as num).toString()
        : '',
  );
  late bool _best = widget.existing?['bestSeller'] == true;
  late String _image = (widget.existing?['image'] ?? '').toString();
  bool _uploading = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _price.dispose();
    _old.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    if (_uploading) return;
    setState(() => _uploading = true);
    try {
      final url = await ImageService.pickAndUpload(
        'products',
        storeId: widget.storeId,
      );
      if (url != null && mounted) setState(() => _image = url);
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر رفع الصورة. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _save() {
    final name = _name.text.trim();
    final price = double.tryParse(_price.text.trim().replaceAll(',', '.'));
    if (name.isEmpty || name.length > 120) {
      setState(() => _error = 'اكتب اسم الصنف (حتى 120 حرف).');
      return;
    }
    if (price == null || price <= 0 || price > 20000) {
      setState(() => _error = 'اكتب سعر صحيح (من 1 لحد 20000).');
      return;
    }
    double? oldPrice;
    final oldTxt = _old.text.trim().replaceAll(',', '.');
    if (oldTxt.isNotEmpty) {
      oldPrice = double.tryParse(oldTxt);
      if (oldPrice == null || oldPrice <= price || oldPrice > 20000) {
        setState(
          () => _error = 'السعر قبل الخصم لازم يكون أكبر من السعر الحالي.',
        );
        return;
      }
    }
    Navigator.of(context).pop(
      _ProductForm(name, price, _image, oldPrice: oldPrice, bestSeller: _best),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.existing == null ? 'إضافة صنف' : 'تعديل صنف'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'اسم الصنف'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _price,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'السعر الحالي (ج.م)',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _old,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: const InputDecoration(
                labelText: 'السعر قبل الخصم (اختياري - لعمل عرض)',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _best,
              onChanged: (v) => setState(() => _best = v),
              title: const Text('الأكثر مبيعًا'),
            ),
            const SizedBox(height: 4),
            if (_image.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  _image,
                  height: 110,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) =>
                      const Icon(Icons.broken_image_outlined),
                ),
              ),
            TextButton.icon(
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.image_outlined),
              label: Text(_image.isEmpty ? 'اختيار صورة' : 'تغيير الصورة'),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(_error!, style: const TextStyle(color: kDanger)),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('إلغاء'),
        ),
        FilledButton(onPressed: _save, child: const Text('حفظ')),
      ],
    );
  }
}

enum _OfferMode { percent, price, text }

/// اختيار صاحب المحل من نافذة العرض.
class _OfferChoice {
  final bool cancel;
  final _OfferMode? mode;
  final double? offerPrice;
  final String? text;
  final DateTime? endsAt;

  const _OfferChoice.cancel() : cancel = true, mode = null, offerPrice = null, text = null, endsAt = null;

  const _OfferChoice.apply({
    required this.mode,
    this.offerPrice,
    this.text,
    this.endsAt,
  }) : cancel = false;
}

/// نافذة «عمل عرض على صنف»: نسبة مئوية، سعر مباشر، أو نص حر، مع تاريخ انتهاء اختياري.
class _OfferDialog extends StatefulWidget {
  final String name;
  final double base;
  final bool hasOffer;
  final DateTime? initialEndsAt;

  const _OfferDialog({
    required this.name,
    required this.base,
    required this.hasOffer,
    this.initialEndsAt,
  });

  @override
  State<_OfferDialog> createState() => _OfferDialogState();
}

class _OfferDialogState extends State<_OfferDialog> {
  static const _quickPercents = [10, 15, 20, 25, 30, 40, 50];
  static const _textSuggestions = [
    '2+1 مجانًا',
    'اشترِ 1 واحصل على 1 مجانًا',
    'هدية مع الطلب',
    'خصم للكمية',
    'عرض اليوم فقط',
  ];

  _OfferMode _mode = _OfferMode.percent;
  final _pct = TextEditingController();
  final _price = TextEditingController();
  final _text = TextEditingController();
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    final e = widget.initialEndsAt;
    if (e != null && !isOfferExpired(e, DateTime.now())) _endsAt = e;
  }

  @override
  void dispose() {
    _pct.dispose();
    _price.dispose();
    _text.dispose();
    super.dispose();
  }

  /// أرقام عربية/فاصلة → أرقام إنجليزية عشان tryParse.
  static double? _num(String raw) {
    const ar = '٠١٢٣٤٥٦٧٨٩';
    final b = StringBuffer();
    for (final c in raw.trim().split('')) {
      final i = ar.indexOf(c);
      b.write(i >= 0 ? '$i' : (c == '،' || c == ',' || c == '٫' ? '.' : c));
    }
    return double.tryParse(b.toString());
  }

  /// العرض الحالي حسب الأدخلات، أو null لو غير صالح (بنستخدم نموذج ProductOffer للتحقق).
  ProductOffer? get _offer {
    try {
      switch (_mode) {
        case _OfferMode.percent:
          final v = _num(_pct.text);
          if (v == null) return null;
          return ProductOffer.percentage(
            originalPrice: widget.base,
            percentage: v,
          );
        case _OfferMode.price:
          final v = _num(_price.text);
          if (v == null) return null;
          return ProductOffer.fixedPrice(
            originalPrice: widget.base,
            offerPrice: v,
          );
        case _OfferMode.text:
          final t = _text.text.trim();
          if (t.length > 60) return null;
          return ProductOffer.text(
            originalPrice: widget.base,
            description: t,
          );
      }
    } on ArgumentError {
      return null;
    }
  }

  String? get _hint {
    switch (_mode) {
      case _OfferMode.percent:
        if (_pct.text.trim().isEmpty) return null;
        return _offer == null ? 'اكتب نسبة بين 1 و 99.' : null;
      case _OfferMode.price:
        if (_price.text.trim().isEmpty) return null;
        return _offer == null
            ? 'السعر الجديد لازم يكون أقل من ${formatPrice(widget.base)}.'
            : null;
      case _OfferMode.text:
        return null;
    }
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _endsAt ?? now.add(const Duration(days: 1)),
      firstDate: DateTime(now.year, now.month, now.day),
      lastDate: now.add(const Duration(days: 365)),
      helpText: 'آخر يوم للعرض',
    );
    if (picked != null) {
      // العرض بيفضل شغال لحد آخر اليوم المختار.
      setState(() {
        _endsAt = DateTime(picked.year, picked.month, picked.day, 23, 59, 59);
      });
    }
  }

  void _submit() {
    final o = _offer;
    if (o == null) return;
    Navigator.pop(
      context,
      _OfferChoice.apply(
        mode: _mode,
        offerPrice: o.offerPrice,
        text: o.description,
        endsAt: _endsAt,
      ),
    );
  }

  Widget _preview() {
    final o = _offer;
    if (o == null) return const SizedBox.shrink();
    final String line;
    if (o.type == ProductOfferType.text) {
      line = 'هيظهر على الصنف شارة: «${o.description}»';
    } else {
      line =
          'السعر بعد الخصم: ${formatPrice(o.effectivePrice)}'
          '  (وفّر ${formatPrice(o.savings)} — ${o.calculatedPercentage?.toStringAsFixed(0)}%)';
    }
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 12),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: kPrimarySoft,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(line, style: const TextStyle(fontWeight: FontWeight.w800)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hint = _hint;
    return AlertDialog(
      title: Text(
        'عرض على "${widget.name}"',
        style: const TextStyle(fontSize: 16),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'السعر الأصلي: ${formatPrice(widget.base)}',
              style: TextStyle(color: kMuted),
            ),
            const SizedBox(height: 12),
            SegmentedButton<_OfferMode>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: _OfferMode.percent, label: Text('نسبة %')),
                ButtonSegment(value: _OfferMode.price, label: Text('سعر مباشر')),
                ButtonSegment(value: _OfferMode.text, label: Text('نص حر')),
              ],
              selected: {_mode},
              onSelectionChanged: (v) => setState(() => _mode = v.first),
            ),
            const SizedBox(height: 12),
            if (_mode == _OfferMode.percent) ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final p in _quickPercents)
                    ActionChip(
                      label: Text('$p%'),
                      onPressed: () => setState(() => _pct.text = '$p'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _pct,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: const InputDecoration(
                  labelText: 'أو اكتب نسبة الخصم %',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ] else if (_mode == _OfferMode.price) ...[
              TextField(
                controller: _price,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: 'بدل ${formatPrice(widget.base)} يبقى',
                  suffixText: 'ج.م',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ] else ...[
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final t in _textSuggestions)
                    ActionChip(
                      label: Text(t),
                      onPressed: () => setState(() => _text.text = t),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _text,
                maxLength: 60,
                decoration: const InputDecoration(
                  labelText: 'نص العرض (مثل 2+1 مجانًا)',
                ),
                onChanged: (_) => setState(() {}),
              ),
            ],
            if (hint != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(hint, style: TextStyle(color: kDanger, fontSize: 12)),
              ),
            _preview(),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickDate,
                    icon: const Icon(Icons.event_outlined, size: 18),
                    label: Text(
                      _endsAt == null
                          ? 'تاريخ انتهاء (اختياري)'
                          : 'حتى ${_endsAt!.day}/${_endsAt!.month}/${_endsAt!.year}',
                    ),
                  ),
                ),
                if (_endsAt != null)
                  IconButton(
                    tooltip: 'بدون تاريخ انتهاء',
                    icon: const Icon(Icons.close),
                    onPressed: () => setState(() => _endsAt = null),
                  ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        if (widget.hasOffer)
          TextButton(
            onPressed: () => Navigator.pop(context, const _OfferChoice.cancel()),
            child: Text('إلغاء العرض', style: TextStyle(color: kDanger)),
          ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('رجوع'),
        ),
        FilledButton(
          onPressed: _offer == null ? null : _submit,
          child: const Text('تفعيل العرض'),
        ),
      ],
    );
  }
}


/// الطلبات الخاصة التي يرسلها العملاء عندما لا يجدون المنتج في قائمة المحل.
class _OwnerSpecialRequestsTab extends StatelessWidget {
  final String storeId;
  const _OwnerSpecialRequestsTab({required this.storeId});

  @override
  Widget build(BuildContext context) {
    final stream = FirebaseFirestore.instance
        .collection('special_requests')
        .where('storeId', isEqualTo: storeId)
        .orderBy('createdAt', descending: true)
        .limit(50)
        .snapshots();

    return StreamBuilder<QuerySnapshot<_Json>>(
      stream: stream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return const Center(child: Text('تعذر تحميل الطلبات الخاصة.'));
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator());
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return const EmptyState(
            icon: Icons.inbox_outlined,
            title: 'لا توجد طلبات خاصة',
            message: 'طلبات المنتجات غير الموجودة هتظهر هنا.',
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: docs.length,
          separatorBuilder: (_, _) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final data = docs[index].data();
            final created = data['createdAt'];
            final date = created is Timestamp ? created.toDate() : null;
            return Card(
              color: Colors.white,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      (data['description'] ?? '').toString().isEmpty
                          ? 'طلب بدون وصف نصي'
                          : (data['description'] ?? '').toString(),
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    const SizedBox(height: 6),
                    Text('الكمية: ${data['quantity'] ?? 1}'),
                    if (date != null)
                      Text('${date.day}/${date.month}/${date.year} • ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}',
                          style: TextStyle(color: Colors.grey.shade600, fontSize: 12)),
                    if ((data['imageUrl'] ?? '').toString().isNotEmpty) ...[
                      const SizedBox(height: 8),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: Image.network(
                          data['imageUrl'].toString(),
                          height: 150,
                          fit: BoxFit.contain,
                          errorBuilder: (_, _, _) => const Text('تعذر عرض الصورة المرفقة'),
                        ),
                      ),
                    ],
                    if ((data['voiceBase64'] ?? '').toString().isNotEmpty)
                      _SpecialVoicePlayer(encoded: data['voiceBase64'].toString()),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _SpecialVoicePlayer extends StatefulWidget {
  final String encoded;
  const _SpecialVoicePlayer({required this.encoded});

  @override
  State<_SpecialVoicePlayer> createState() => _SpecialVoicePlayerState();
}

class _SpecialVoicePlayerState extends State<_SpecialVoicePlayer> {
  late final audio.AudioPlayer _player = audio.AudioPlayer();
  StreamSubscription<void>? _completionSubscription;
  bool _playing = false;

  @override
  void initState() {
    super.initState();
    _completionSubscription = _player.onPlayerComplete.listen((_) {
      if (mounted) setState(() => _playing = false);
    });
  }

  @override
  void dispose() {
    _completionSubscription?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _play() async {
    try {
      await _player.stop();
      await _player.setSource(audio.BytesSource(base64Decode(widget.encoded)));
      await _player.resume();
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تعذر تشغيل الرسالة الصوتية.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: OutlinedButton.icon(
      onPressed: _playing
          ? () async {
              await _player.pause();
              if (mounted) setState(() => _playing = false);
            }
          : _play,
      icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
      label: Text(_playing ? 'إيقاف مؤقت' : 'تشغيل الرسالة الصوتية'),
    ),
  );
}
