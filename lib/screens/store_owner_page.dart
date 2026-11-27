import 'dart:async';
import 'dart:convert';

import 'package:audioplayers/audioplayers.dart' as audio;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/owner_products_freshness.dart';

import '../utils/bulk_products.dart';
import '../widgets/share_actions.dart';
import '../utils/product_autofill.dart';
import '../utils/product_photo.dart';
import '../utils/store_product_templates.dart';
import '../services/order_gateway.dart';
import 'referral_campaign_page.dart';
import '../models/order.dart';
import '../models/product_offer.dart';
import '../services/catalog_service.dart';
import '../services/store_highlights.dart';
import '../services/read_meter.dart';
import '../services/catalog_sync.dart';
import '../services/customer_rating_service.dart';
import '../services/driver_service.dart';
import '../models/product.dart';
import '../services/image_service.dart';
import '../widgets/stock_photo_picker.dart';
import '../services/navigation.dart' show roleInfoOverride;
import '../services/role_service.dart';
import '../services/staff_order_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/store_orders_split.dart';
import '../utils/store_today_summary.dart';
import '../widgets/customer_rating_dialog.dart';
import '../widgets/dialogs.dart';
import '../widgets/empty_state.dart';
import '../widgets/feedback_fab.dart';
import '../widgets/option_groups_editor.dart';
import '../widgets/staff_header.dart';
import '../widgets/staff_notification_permission_banner.dart';
import '../widgets/order_timer.dart';
import '../widgets/status_pill.dart';
import '../widgets/unanswered_orders_alert.dart';
import '../services/store_fee_service.dart';
import '../widgets/app_snack.dart';

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

const _storeOrderLimit = 100;

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
      stream: StaffOrderService.watchForStore(storeId, limit: _storeOrderLimit),
      builder: (context, snapshot) {
        final orders = snapshot.data ?? const <AppOrder>[];
        return DefaultTabController(
          length: 2,
          child: Scaffold(
            floatingActionButton: const FeedbackFab(),
            body: NestedScrollView(
              headerSliverBuilder: (context, _) => [
                SliverToBoxAdapter(
                  child: Column(
                    children: [
                      StaffHeader(
                        title: 'لوحة المحل',
                        subtitle: name.isEmpty
                            ? 'حساب صاحب المحل'
                            : 'أهلاً $name',
                      ),
                      const StaffNotificationPermissionBanner(),
                      _ShopStatusBar(storeId: storeId),
                      if (OrderGateway.referralCampaignEnabled)
                        const ReferralCampaignLink(storeOwner: true),
                      UnansweredOrdersAlert(orders: orders),
                      _TodaySummaryBar(orders: orders),
                    ],
                  ),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _TabsDelegate(
                    MediaQuery.paddingOf(context).top,
                    TabBar(
                      labelColor: AppColors.purple,
                      unselectedLabelColor: kMuted,
                      indicatorColor: AppColors.orange,
                      labelStyle: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: AppTypography.body,
                      ),
                      tabs: const [
                        Tab(text: 'الطلبات'),
                        Tab(text: 'الأصناف والعروض'),
                      ],
                    ),
                  ),
                ),
              ],
              body: TabBarView(
                children: [
                  _OwnerOrdersTab(
                    storeId: storeId,
                    orders: orders,
                    loading: !snapshot.hasData && !snapshot.hasError,
                    error: snapshot.error,
                  ),
                  _OwnerProductsTab(storeId: storeId),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _TabsDelegate extends SliverPersistentHeaderDelegate {
  final double top;
  final TabBar bar;
  _TabsDelegate(this.top, this.bar);

  // لما الشريط يثبت فوق، بنسيب مكان لشريط الحالة.
  @override
  double get minExtent => bar.preferredSize.height + top;
  @override
  double get maxExtent => bar.preferredSize.height + top;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Material(
        color: Colors.white,
        elevation: overlaps ? 2 : 0,
        child: Padding(
          padding: EdgeInsets.only(top: top),
          child: bar,
        ),
      );

  @override
  bool shouldRebuild(covariant _TabsDelegate old) => old.top != top;
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
        await CatalogSync.storeChanged(widget.storeId);
        if (!mounted) return;
        messenger.showSnackBar(
          appSnack('تم تحديث صورة المحل.'),
        );
      }
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(
        appSnack('تعذر تحديث الصورة: ${_why(e)}'),
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
                                  fontWeight: FontWeight.w800,
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
  StreamSubscription<DocumentSnapshot<_Json>>? _indexRefresh;

  @override
  void initState() {
    super.initState();
    // تقييمات العملاء بتتكتب على مستند المحل بس (العميل ما يكتبش في الفهرس)، فلما صاحب المحل
    // يفتح لوحته بنحدّث خانة محله في الفهرس لو التقييم اتغير. نفس الاستعلام = من غير قراءات زيادة.
    _indexRefresh = _stream.listen((snap) {
      final data = snap.data();
      if (data != null) {
        CatalogSync.refreshIfRatingChanged(widget.storeId, data);
      }
    });
  }

  @override
  void dispose() {
    _indexRefresh?.cancel();
    super.dispose();
  }

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
        await CatalogSync.storeChanged(widget.storeId);
        await CatalogService.bump();
        messenger.showSnackBar(
          appSnack('تم تغيير صورة المحل.'),
        );
      }
    } catch (e) {
      messenger.showSnackBar(
        appSnack('تعذر تغيير الصورة: ${_why(e)}'),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// فتح/غلق المحل. المغلق بيفضل ظاهر للعملاء ومكتوب عليه «مغلق الآن» ومايستقبلش طلبات.
  /// (الإخفاء الكامل من الإدارة بس.)
  Future<void> _setOpen(bool value) async {
    if (_busy) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      await FirebaseFirestore.instance
          .collection('stores')
          .doc(widget.storeId)
          .update({'isOpen': value, 'updatedAt': FieldValue.serverTimestamp()});
      final indexed = await CatalogSync.storeChanged(widget.storeId);
      await CatalogService.bump();
      if (!indexed) {
        await CatalogSync.markIndexPending(widget.storeId);
        messenger.showSnackBar(
          appSnack('اتغيرت حالة المحل، بس ظهوره للعملاء هيتحدث لما الاتصال يتحسن.'),
        );
      }
    } catch (_) {
      messenger.showSnackBar(
        appSnack('تعذر تغيير حالة المحل، جرّب تاني.'),
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
        final isOpen = (data['isOpen'] as bool?) ?? true;
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
                                        fontSize: 21,
                                        fontWeight: FontWeight.w800,
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
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          !active
                              ? 'المحل مخفي أو بانتظار تفعيل الإدارة'
                              : isOpen
                                  ? 'المحل مفتوح ويستقبل طلبات'
                                  : 'المحل مغلق الآن (ظاهر للعملاء ومش بيستقبل طلبات)',
                          style: TextStyle(
                            color: active && isOpen ? kSuccess : kDanger,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                        // من ratingSum/ratingCount على مستند المحل نفسه (المستمع ده): صفر قراءات،
                        // بدل قراءة لحد 300 تقييم مع كل فتحة للوحة.
                        Text(
                          'تقييم المحل: ${RatingSummary.fromStore(data).text}',
                          style: TextStyle(color: kMuted, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: active && isOpen,
                    onChanged: _busy || !active ? null : _setOpen,
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: kPrimary,
                        side: BorderSide(color: kPrimary),
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
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
                      style: FilledButton.styleFrom(
                        backgroundColor: kPrimary,
                        foregroundColor: Colors.white,
                        textStyle: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      onPressed: () =>
                          DefaultTabController.of(context).animateTo(1),
                      icon: const Icon(Icons.local_offer_outlined, size: 18),
                      label: const Text('عمل عرض'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.outlined(
                    key: const Key('owner-store-qr'),
                    tooltip: 'كود QR ومشاركة المحل',
                    color: kPrimary,
                    style: IconButton.styleFrom(
                      side: BorderSide(color: kPrimary),
                    ),
                    onPressed: () => showStoreQrSheet(
                      context,
                      storeName: shopName,
                      storeId: widget.storeId,
                    ),
                    icon: const Icon(Icons.qr_code_2_rounded, size: 20),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// ───────────────────────── الطلبات ─────────────────────────

class _OwnerOrdersTab extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (error != null) {
      return EmptyState(
        icon: Icons.lock_outline,
        title: 'تعذر تحميل الطلبات',
        message: _why(error!),
      );
    }
    if (loading) {
      return Center(child: CircularProgressIndicator(color: kPrimary));
    }
    // الصفحة دي للشغل الجاري بس. الطلبات اللي خلصت في صفحة «الطلبات المنتهية».
    final current = orders.where(isOpenOrder).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: OutlinedButton.icon(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => StoreClosedOrdersPage(storeId: storeId, orders: orders),
              ),
            ),
            icon: const Icon(Icons.inventory_2_outlined, size: 18),
            label: const Text('الطلبات المنتهية والحساب'),
          ),
        ),
        Expanded(
          child: current.isEmpty
              ? const EmptyState(
                  icon: Icons.receipt_long_outlined,
                  title: 'مفيش طلبات شغالة دلوقتي',
                  message: 'الطلبات الجديدة هتظهر هنا، والمنتهية في «الطلبات المنتهية والحساب».',
                )
              : ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: current.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _OwnerOrderCard(
                    key: ValueKey(current[i].id),
                    order: current[i],
                  ),
                ),
        ),
      ],
    );
  }
}

/// الطلبات اللي خلصت (تم التوصيل/ملغي) لسه ما اتقفلش حسابها مع وصّلي.
/// قسمين: «البضاعة» (الطلبات وأصنافها) و«الفلوس» (رسوم وصّلي والمتبقي).
/// بعد ما الإدارة تقفل الحساب، الطلبات القديمة بتختفي من هنا.
class StoreClosedOrdersPage extends StatefulWidget {
  final String storeId;
  final List<AppOrder> orders;
  const StoreClosedOrdersPage({super.key, required this.storeId, required this.orders});

  @override
  State<StoreClosedOrdersPage> createState() => _StoreClosedOrdersPageState();
}

class _StoreClosedOrdersPageState extends State<StoreClosedOrdersPage> {
  bool _goods = true;
  // قراءة واحدة (رصيد + تجميع رسوم) بتتشارك بين الفلتر وقسم الفلوس.
  late Future<StoreFeeSummary> _future = StoreFeeService.load(widget.storeId);

  void _reload() => setState(() => _future = StoreFeeService.load(widget.storeId));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('الطلبات المنتهية والحساب')),
      body: FutureBuilder<StoreFeeSummary>(
        future: _future,
        builder: (context, snap) {
          if (snap.hasError) {
            return EmptyState(
              icon: Icons.cloud_off_outlined,
              title: 'تعذر تحميل الحساب',
              message: 'اتأكد من الإنترنت وحاول تاني.',
              actionLabel: 'حاول تاني',
              onAction: _reload,
            );
          }
          if (!snap.hasData) {
            return Center(child: CircularProgressIndicator(color: kPrimary));
          }
          final summary = snap.data!;
          final closed = closedOrdersAfterSettlement(widget.orders, summary.settledAt);
          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: SegmentedButton<bool>(
                  segments: [
                    ButtonSegment(value: true, label: Text('البضاعة (${closed.length})')),
                    const ButtonSegment(value: false, label: Text('الفلوس')),
                  ],
                  selected: {_goods},
                  onSelectionChanged: (v) => setState(() => _goods = v.first),
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'السجل من أحدث $_storeOrderLimit طلب للمحل، وبيشمل الطلبات المنتهية بعد آخر تقفيل حساب.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 12.5),
                ),
              ),
              Expanded(
                child: _goods
                    ? (closed.isEmpty
                        ? const EmptyState(
                            icon: Icons.inventory_2_outlined,
                            title: 'مفيش طلبات منتهية',
                            message: 'الطلبات اللي اتقفل حسابها بتتشال من هنا.',
                          )
                        : ListView.separated(
                            padding: const EdgeInsets.all(16),
                            itemCount: closed.length,
                            separatorBuilder: (_, _) => const SizedBox(height: 12),
                            itemBuilder: (context, i) => ClosedOrderCompactCard(order: closed[i]),
                          ))
                    : ListView(
                        padding: const EdgeInsets.all(16),
                        children: [
                          // حساب وصّلي الإجمالي (المستحق/المدفوع/المتبقي) منفصل عن كروت الأيام.
                          Card(
                            child: Padding(
                              padding: const EdgeInsets.all(14),
                              child: StoreFeeSummaryView(
                                storeId: widget.storeId,
                                future: _future,
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                            child: Text(
                              'تفصيل الطلبات بالأيام. رسوم كل يوم هي اللي اتجمعت على طلباته، مش رصيد لسه مطلوب دفعه (المتبقي الفعلي في الكارت اللي فوق).',
                              style: TextStyle(fontSize: 12.5, height: 1.4),
                            ),
                          ),
                          for (final g in groupClosedByDay(closed)) ClosedDayCard(group: g),
                        ],
                      ),
              ),
            ],
          );
        },
      ),
    );
  }
}

String _closedOrderLabel(AppOrder order) {
  if (order.status == OrderStatus.cancelled &&
      order.lastDeliveryIssueId.isNotEmpty) {
    return 'مرتجع';
  }
  return order.status.label;
}

/// كارت يوم واحد: عدد الطلبات، البضاعة، ورسوم وصّلي (للمسلّم بس)، وتفاصيل كل فاتورة بالضغط.
class ClosedDayCard extends StatelessWidget {
  final ClosedDayGroup group;
  const ClosedDayCard({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    final m = group.money;
    final d = group.day;
    final title = '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
    return Card(
      margin: const EdgeInsets.only(top: 10),
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            'مكتمل ${m.completedCount}${m.cancelledCount > 0 ? '  •  ملغي ${m.cancelledCount}' : ''}\n'
            'البضاعة: ${formatPrice(m.goodsTotal)}  •  رسوم وصّلي المسجّلة: ${formatPrice(m.serviceFeeTotal)}',
            style: const TextStyle(height: 1.45),
          ),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final o in group.orders)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${formatDateTime(closedOrderTime(o)!)}'
                      '${o.status == OrderStatus.cancelled ? ' • ${_closedOrderLabel(o)}' : ''}',
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  Text(
                    o.status == OrderStatus.cancelled
                        ? '—'
                        : '${formatPrice(o.subtotal)} • '
                            '${o.serviceFee == null ? 'الرسوم غير مسجّلة' : 'رسوم ${formatPrice(o.serviceFee!)}'}',
                    style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// بطاقة طلب منتهٍ مختصرة: العميل، التاريخ، الحالة، قيمة البضاعة، وزر «عرض التفاصيل».
class ClosedOrderCompactCard extends StatelessWidget {
  final AppOrder order;
  const ClosedOrderCompactCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    final o = order;
    final t = closedOrderTime(o);
    final who = o.customerName.trim().isNotEmpty ? o.customerName.trim() : 'عميل';
    return Card(
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        title: Row(
          children: [
            Expanded(child: Text(who, style: const TextStyle(fontWeight: FontWeight.w800))),
            Text(
              _closedOrderLabel(o),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: o.status == OrderStatus.cancelled ? Colors.red.shade700 : Colors.green.shade700,
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text(
            '${t != null ? formatDateTime(t) : ''}\n'
            'قيمة البضاعة: ${formatPrice(o.subtotal)}',
            style: const TextStyle(height: 1.45),
          ),
        ),
        trailing: const Text('عرض التفاصيل', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        children: [
          for (final line in o.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(
                      '${line.qty} × ${line.name}'
                      '${line.options.isNotEmpty ? ' (${line.options.join('، ')})' : ''}',
                      style: const TextStyle(height: 1.35),
                    ),
                  ),
                  Text('${formatPrice(line.price)} × ${line.qty} = ${formatPrice(line.total)}',
                      style: const TextStyle(fontSize: 12.5)),
                ],
              ),
            ),
          const Divider(height: 16),
          Row(
            children: [
              const Expanded(child: Text('المجموع (البضاعة)', style: TextStyle(fontWeight: FontWeight.w800))),
              Text(formatPrice(o.subtotal), style: const TextStyle(fontWeight: FontWeight.w800)),
            ],
          ),
          if (o.status == OrderStatus.delivered) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Expanded(child: Text('رسوم التوصيل')),
                Text(formatPrice(o.courierFee)),
              ],
            ),
            Row(
              children: [
                const Expanded(child: Text('رسوم وصّلي المسجّلة')),
                Text(o.serviceFee == null
                    ? 'غير مسجّلة'
                    : formatPrice(o.serviceFee!)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _OwnerOrderCard extends StatefulWidget {
  final AppOrder order;
  const _OwnerOrderCard({super.key, required this.order});

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
        appSnack(_unavailable.isEmpty
                ? 'تم شيل علامة النقص.'
                : 'تم تبليغ العميل. هيكمّل من غير الأصناف دي أو يلغي.'),
      );
    } on StateError catch (e) {
      messenger.showSnackBar(appSnack(e.message));
    } catch (_) {
      messenger.showSnackBar(
        appSnack('تعذر تبليغ العميل. جرّب تاني.'),
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
                  child: Text('اختيار مندوب تابع للمحل', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
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
      messenger.showSnackBar(appSnack('تم تعيين ' + courier.name + ' كمندوب للمحل.'));
    } catch (error) {
      messenger.showSnackBar(appSnack(error is StateError ? error.message : 'تعذر تعيين المندوب.'));
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
        appSnack('تعذر تأكيد جاهزية الطلب. ممكن حالته اتغيّرت، جرّب تاني.'),
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
        appSnack('تم تأكيد استلام المحل للمرتجع.'),
      );
    } catch (error) {
      messenger.showSnackBar(
        appSnack('تعذر تأكيد الاستلام: $error'),
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
            'تم تأكيد استلام المرتجع، والطلب اتقفل.',
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
          appSnack('تم تأكيد استلام النقدية وإغلاق الطلب.'),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          appSnack(error is StateError ? error.message : 'تعذر تأكيد استلام النقدية.'),
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
        appSnack('تعذر التحقق من التقييم السابق: $error'),
      );
      return;
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted) return;
    if (alreadyRated) {
      setState(() => _customerRated = true);
      messenger.showSnackBar(
        appSnack('تم تقييم تعامل العميل على هذا الطلب من قبل.'),
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
        appSnack('تم تسجيل تقييم العميل. شكرًا لمشاركتك.'),
      );
    } catch (error) {
      messenger.showSnackBar(
        appSnack(error is StateError ? error.message : 'تعذر تسجيل تقييم العميل.'),
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
        appSnack('تعذر تحديث الطلب. ممكن حالته اتغيّرت، جرّب تاني.'),
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
                style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800),
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
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
            title: const Text('تفاصيل الطلب'),
            subtitle: Text('عدد الأصناف: ${o.items.length}'),
            children: [
              // نفس شكل الفاتورة الحرارية (ورق أبيض وخط متقطع)، بس نص عادي
              // عشان المحل يقدر يعلّم على الأصناف الناقصة.
              Container(
                key: const Key('owner-thermal-items'),
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFFEFA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: kLine),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
              for (final line in o.items)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${line.name} × ${line.qty}',
                              style: TextStyle(
                                fontWeight: FontWeight.w700,
                                color: _unavailable.contains(line.name)
                                    ? kDanger
                                    : null,
                                decoration: _unavailable.contains(line.name)
                                    ? TextDecoration.lineThrough
                                    : null,
                              ),
                            ),
                            if (line.options.isNotEmpty)
                              Text(line.options.join('، '), style: text.bodySmall),
                          ],
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
              if (o.specialRequest != null) ...[
                const SizedBox(height: 10),
                _SpecialRequestBox(data: o.specialRequest!),
              ],
              if (o.notes.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text('ملاحظات العميل: ${o.notes}'),
              ],
              const Divider(height: 18),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'إجمالي الأصناف',
                      style: text.titleSmall?.copyWith(fontWeight: FontWeight.w900),
                    ),
                  ),
                  Text(
                    formatPrice(o.subtotal),
                    style: text.titleMedium?.copyWith(fontWeight: FontWeight.w900),
                  ),
                ],
              ),
                  ],
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
    // مزامنة قائمة اتقطعت قبل كده (التطبيق اتقفل/النت قطع بعد حفظ صنف): نكمّلها في الخلفية.
    CatalogSync.resumePending(widget.storeId);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _say(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(appSnack(message));
  }

  String get _tokenKey => 'owner_products_token_${widget.storeId}';
  String get _fullLoadKey => 'owner_products_full_${widget.storeId}';

  /// بصمة القائمة المجمّعة من الخادم (قراءة واحدة). بترجع (البصمة، فشل؟).
  Future<(String?, bool)> _readMenuToken() async {
    try {
      final m = await _storeRef
          .collection('menu')
          .doc('current')
          .get(const GetOptions(source: Source.server));
      ReadMeter.document('owner:menu-token', m);
      final data = m.data();
      final at = data?['updatedAt'];
      return (
        menuFreshnessToken(
          exists: m.exists,
          updatedAtMs: at is Timestamp ? at.millisecondsSinceEpoch : null,
          count: (data?['count'] as num?)?.toInt(),
        ),
        false,
      );
    } catch (_) {
      return (null, true);
    }
  }

  Future<void> _saveToken(SharedPreferences prefs, String? token) async {
    if (token == null) {
      await prefs.remove(_tokenKey);
    } else {
      await prefs.setString(_tokenKey, token);
    }
  }

  /// [fromCache]: بعد تعديل من الجهاز ده، Firestore بيطبّق التعديل على الكاش المحلي فورًا،
  /// فبنقرا من الكاش (صفر قراءات للأصناف) ونحدّث بصمة القائمة بس (قراءة واحدة).
  /// [force]: «إعادة المحاولة» = تحميل كامل من الخادم.
  /// غير كده: بنقارن بصمة القائمة المجمّعة (قراءة واحدة) بآخر تحميل كامل، ونقرا
  /// الأصناف من الخادم (لحد 200 قراءة) بس لو حاجة اتغيرت من جهاز تاني.
  Future<void> _load({bool fromCache = false, bool force = false}) async {
    setState(() {
      _loading = true;
      _error = false;
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      final query = _col.orderBy('name').limit(_limit);
      QuerySnapshot<_Json>? cached;
      if (!force) {
        try {
          final c = await query.get(const GetOptions(source: Source.cache));
          if (c.docs.isNotEmpty) cached = c;
        } catch (_) {}
      }

      // البصمة بتتقري قبل الأصناف: لو حصل تعديل في النص، البصمة المتسجلة هتبقى
      // أقدم، فأول فتح جاي يعيد التحميل (آمن، مش العكس).
      final (serverToken, tokenFailed) = await _readMenuToken();

      final OwnerProductsSource source;
      if (fromCache && cached != null) {
        // تعديل من الجهاز ده: الكاش فيه التعديل، والبصمة الجديدة بتاعته.
        source = OwnerProductsSource.cache;
        if (!tokenFailed) await _saveToken(prefs, serverToken);
      } else {
        final fullMs = prefs.getInt(_fullLoadKey);
        source = ownerProductsSource(
          force: force,
          hasCache: cached != null,
          tokenReadFailed: tokenFailed,
          serverToken: serverToken,
          savedToken: prefs.getString(_tokenKey),
          lastFullLoad: fullMs == null ? null : DateTime.fromMillisecondsSinceEpoch(fullMs),
          now: DateTime.now(),
        );
      }

      final QuerySnapshot<_Json> snap;
      if (source == OwnerProductsSource.cache) {
        snap = cached!;
      } else {
        snap = await query.get(const GetOptions(source: Source.server));
        await prefs.setInt(_fullLoadKey, DateTime.now().millisecondsSinceEpoch);
        if (!tokenFailed) await _saveToken(prefs, serverToken);
      }
      ReadMeter.query('owner:products', snap);
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

  /// بعد أي تعديل صنف: القائمة المجمّعة ← ملخص العروض ← الفهرس ← رقم الإصدار
  /// (الترتيب في CatalogSync.afterProductsChanged)، وبعدها إعادة عرض القائمة من الكاش.
  /// بيرجع true لو ملخص العروض اتحدث.
  Future<bool> _afterProductChange(String productId) async {
    final ok = await CatalogSync.afterProductsChanged(
      widget.storeId,
      productIds: [productId],
    );
    await _load(fromCache: true);
    return ok;
  }

  Future<void> _edit(QueryDocumentSnapshot<_Json>? doc, {bool copy = false}) async {
    final original = doc?.data();
    final draft = copy && original != null
        ? <String, dynamic>{...original, 'name': '${original['name']} نسخة'}
        : original;
    final result = await showDialog<_ProductForm>(
      context: context,
      builder: (_) => _ProductDialog(
        existing: draft, storeId: widget.storeId,
      ),
    );
    if (result == null || !mounted) return;
    final key = normalizeProductKey(result.name);
    // دون استعلام إضافي: استخدم الأصناف التي حمّلتها صفحة التاجر بالفعل.
    if (_docs.any((d) => d.id != (copy ? null : doc?.id) &&
        normalizeProductKey((d.data()['name'] ?? '').toString()) == key)) {
      _say('الصنف ده موجود بالفعل. عدّل الصنف الموجود أو غيّر الاسم.');
      return;
    }

    try {
      final newRef = doc == null || copy ? _col.doc() : null;
      final savedId = newRef?.id ?? doc!.id;
      // قبل الكتابة: لو التطبيق اتقفل قبل مزامنة القائمة، تتكمّل أول ما الصفحة تتفتح.
      await CatalogSync.markPending(widget.storeId, [savedId]);
      if (newRef != null) {
        await newRef.set({
          'name': result.name,
          'price': result.price,
          'image': result.image,
          if (result.oldPrice != null) 'oldPrice': result.oldPrice,
          if (result.bestSeller) 'bestSeller': true,
          if (result.description.isNotEmpty) 'description': result.description,
          if (result.optionGroups.isNotEmpty)
            'optionGroups': result.optionGroups.map((g) => g.toMap()).toList(),
          'isAvailable': true,
          'available': true,
          'createdAt': FieldValue.serverTimestamp(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        // العدّاد ثانوي: فشله ما يمنعش تحديث الملخص والإصدار ولا يخلّي الحفظ يبان فاشل.
        try {
          await _syncCount();
        } catch (_) {}
      } else {
        await doc!.reference.update({
          'name': result.name,
          'price': result.price,
          'image': result.image,
          'oldPrice': result.oldPrice ?? FieldValue.delete(),
          'bestSeller': result.bestSeller,
          'description': result.description,
          'optionGroups': result.optionGroups.map((g) => g.toMap()).toList(),
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
      final ok = await _afterProductChange(savedId);
      if (doc == null && !copy) {
        // المسودة لا تُحذف إلا بعد حفظ المنتج بنجاح على Firestore.
        await _ProductDialogState.clearNewDraft(widget.storeId);
      }
      _say(StoreHighlights.withNote('تم حفظ الصنف', ok));
    } catch (e) {
      _say('تعذر حفظ الصنف: ${_why(e)}');
    }
  }

  /// كتابة الأصناف في دفعات مع مزامنة الملخص مرة واحدة فقط.
  /// كشف التكرار يعتمد على القائمة المحمّلة محليًا (أول 200 صنف).
  Future<void> _addProducts(List<BulkProductLine> lines) async {
    final known = _docs.map((d) =>
        normalizeProductKey((d.data()['name'] ?? '').toString())).toSet();
    final unique = <BulkProductLine>[];
    var skipped = 0;
    for (final line in lines) {
      if (!known.add(normalizeProductKey(line.name))) {
        skipped++;
      } else {
        unique.add(line);
      }
    }
    if (unique.isEmpty) {
      _say('كل الأصناف المختارة موجودة بالفعل في القائمة المحمّلة.');
      return;
    }
    if (skipped > 0) {
      final proceed = await confirmDialog(
        context,
        title: 'أصناف مكررة',
        message: 'لقينا $skipped صنف مكرر في القائمة المحمّلة. '
            'هنضيف ${unique.length} صنف بس. تكمل؟',
        confirmLabel: 'إضافة غير المكرر',
      );
      if (!proceed || !mounted) return;
    }
    var added = 0;
    Object? error;
    // Preallocate IDs so the catalog can sync only the newly created products.
    final refs = [for (var i = 0; i < unique.length; i++) _col.doc()];
    await CatalogSync.markPending(widget.storeId, refs.map((r) => r.id).toList());
    try {
      for (var start = 0; start < unique.length; start += 100) {
        final end = start + 100 > unique.length ? unique.length : start + 100;
        final batch = FirebaseFirestore.instance.batch();
        for (var i = start; i < end; i++) {
          final l = unique[i];
          final groups = l.suggestion?.optionGroups ?? const <OptionGroup>[];
          batch.set(refs[i], {
            'name': l.name,
            'price': l.price,
            'image': '',
            if (l.description.isNotEmpty) 'description': l.description,
            if (groups.isNotEmpty)
              'optionGroups': groups.map((g) => g.toMap()).toList(),
            'isAvailable': true,
            'available': true,
            'createdAt': FieldValue.serverTimestamp(),
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
        added += end - start;
      }
    } catch (e) {
      error = e;
    }
    if (added > 0) {
      try { await _syncCount(); } catch (_) {}
      final ok = await CatalogSync.afterProductsChanged(
        widget.storeId,
        productIds: refs.take(added).map((r) => r.id).toList(),
      );
      await _load(fromCache: true);
      _say(error == null
          ? StoreHighlights.withNote('تم إضافة $added صنف', ok)
          : 'اتضاف $added صنف بس: ${_why(error)}');
    } else if (error != null) {
      _say('تعذر إضافة الأصناف: ${_why(error)}');
    }
  }

  Future<void> _bulkAdd() async {
    final lines = await showModalBottomSheet<List<BulkProductLine>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _BulkProductsSheet(),
    );
    if (lines != null && lines.isNotEmpty && mounted) {
      await _addProducts(lines);
    }
  }

  Future<void> _addFromTemplates() async {
    final lines = await showModalBottomSheet<List<BulkProductLine>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => const _ProductTemplatesSheet(),
    );
    if (lines != null && lines.isNotEmpty && mounted) {
      await _addProducts(lines);
    }
  }

  /// تعديل أسعار الأصناف المعروضة فقط، من غير قراءة جديدة. نستبعد الأصناف
  /// عليها عروض حتى لا نفسد السعر قبل الخصم.
  Future<void> _changePricesTogether() async {
    final term = normalizeProductKey(_term);
    final candidates = _docs.where((doc) {
      final m = doc.data();
      final price = m['price'];
      return (term.isEmpty ||
              normalizeProductKey((m['name'] ?? '').toString()).contains(term)) &&
          price is num && price > 0 &&
          m['oldPrice'] is! num &&
          (m['offerText'] ?? '').toString().isEmpty;
    }).toList();
    if (candidates.isEmpty) {
      _say('مفيش أصناف بدون عروض مناسبة للتعديل في القائمة المعروضة.');
      return;
    }
    var input = '';
    String? error;
    final percent = await showDialog<double>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (ctx, refresh) => AlertDialog(
          title: const Text('تعديل أسعار مجموعة'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('هيتعدل سعر ${candidates.length} صنف محمّل في الصفحة فقط. '
                  'الخصومات الحالية مش هتتغير. نسبة سالبة = تخفيض.'),
              const SizedBox(height: 12),
              TextField(
                onChanged: (value) => input = value,
                keyboardType: const TextInputType.numberWithOptions(
                    decimal: true, signed: true),
                decoration: InputDecoration(
                    labelText: 'نسبة التغيير % (مثال 10 أو -5)',
                    errorText: error),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx),
                child: const Text('إلغاء')),
            FilledButton(
              onPressed: () {
                final p = double.tryParse(input.trim().replaceAll(',', '.'));
                if (p == null || p < -80 || p > 100 || p == 0) {
                  refresh(() => error = 'اكتب نسبة بين -80 و100 غير الصفر');
                  return;
                }
                Navigator.pop(ctx, p);
              },
              child: const Text('مراجعة'),
            ),
          ],
        ),
      ),
    );
    if (percent == null || !mounted) return;
    final changes = <(QueryDocumentSnapshot<_Json>, double)>[];
    for (final doc in candidates) {
      final old = (doc.data()['price'] as num).toDouble();
      final updated = adjustedProductPrice(old, percent);
      if (updated > 0 && updated <= 20000 && updated != old) {
        changes.add((doc, updated));
      }
    }
    if (changes.isEmpty) {
      _say('مافيش أسعار صالحة للتحديث (الحد الأقصى 20,000 جنيه).');
      return;
    }
    final yes = await confirmDialog(
      context,
      title: 'تأكيد تعديل الأسعار',
      message: 'تغيير أسعار ${changes.length} صنف بنسبة $percent%؟ '
          'التغيير هيظهر للعملاء بعد مزامنة الكتالوج. '
          'لن يُعدل أي صنف عليه عرض حاليًا.',
      confirmLabel: 'تأكيد التعديل',
    );
    if (!yes || !mounted) return;
    try {
      await CatalogSync.markPending(widget.storeId,
          changes.map((e) => e.$1.id).toList());
      for (var i = 0; i < changes.length; i += 100) {
        final batch = FirebaseFirestore.instance.batch();
        for (final entry in changes.skip(i).take(100)) {
          batch.update(entry.$1.reference, {
            'price': entry.$2,
            'updatedAt': FieldValue.serverTimestamp(),
          });
        }
        await batch.commit();
      }
      final ok = await CatalogSync.afterProductsChanged(
        widget.storeId,
        productIds: changes.map((e) => e.$1.id).toList(),
      );
      await _load(fromCache: true);
      _say(StoreHighlights.withNote('تم تعديل ${changes.length} سعر', ok));
    } catch (e) {
      _say('تعذر إكمال تعديل الأسعار: ${_why(e)}');
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
      await CatalogSync.markPending(widget.storeId, [doc.id]);
      await doc.reference.update(update);
      final ok = await _afterProductChange(doc.id);
      _say(StoreHighlights.withNote(
        choice.cancel ? 'اتلغى العرض' : 'تم تفعيل العرض',
        ok,
      ));
    } catch (e) {
      _say('تعذر تفعيل العرض: ${_why(e)}');
    }
  }

  Future<void> _toggle(QueryDocumentSnapshot<_Json> doc, bool value) async {
    try {
      await CatalogSync.markPending(widget.storeId, [doc.id]);
      await doc.reference.update({
        'available': value,
        'isAvailable': value,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      final ok = await _afterProductChange(doc.id);
      if (!ok) _say(StoreHighlights.withNote('اتغيرت حالة الصنف', ok));
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
      await CatalogSync.markPending(widget.storeId, [doc.id]);
      await doc.reference.delete();
      // العدّاد ثانوي: فشله ما يمنعش تحديث الملخص والإصدار ولا يخلّي الحفظ يبان فاشل.
      try {
        await _syncCount();
      } catch (_) {}
      final ok = await _afterProductChange(doc.id);
      _say(StoreHighlights.withNote('تم حذف الصنف', ok));
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
        onAction: () => _load(force: true),
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
                  // من غير صورة: نفس الصورة التوضيحية اللي العميل بيشوفها (باهتة شوية).
                  child: image.isEmpty
                      ? Opacity(
                          opacity: 0.6,
                          child: Image.network(
                            productPhotoFor(name: (m['name'] ?? '').toString()).url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, _, _) =>
                                Icon(Icons.image_outlined, color: kMuted),
                          ),
                        )
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
              subtitle: Text(
                _priceLine(m, price, available),
                style: TextStyle(color: kMuted, fontSize: 12),
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Transform.scale(
                    scale: 0.8,
                    child: Switch(
                      value: available,
                      onChanged: (v) => _toggle(d, v),
                    ),
                  ),
                  PopupMenuButton<String>(
                    onSelected: (v) {
                      if (v == 'edit') _edit(d);
                      if (v == 'copy') _edit(d, copy: true);
                      if (v == 'offer') _offer(d);
                      if (v == 'delete') _delete(d);
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'offer',
                        child: Text('عمل عرض / خصم'),
                      ),
                      PopupMenuItem(value: 'edit', child: Text('تعديل')),
                      PopupMenuItem(value: 'copy', child: Text('نسخ صنف')),
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
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  key: const Key('owner-bulk-add'),
                  onPressed: _bulkAdd,
                  icon: const Icon(Icons.playlist_add_rounded),
                  label: const Text('إضافة أصناف كتير مرة واحدة (لصق قايمة)'),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(children: [
                Expanded(child: OutlinedButton.icon(
                  key: const Key('owner-product-templates'),
                  onPressed: _addFromTemplates,
                  icon: const Icon(Icons.auto_awesome_outlined),
                  label: const Text('أصناف جاهزة'),
                )),
                const SizedBox(width: 8),
                Expanded(child: OutlinedButton.icon(
                  key: const Key('owner-bulk-prices'),
                  onPressed: _changePricesTogether,
                  icon: const Icon(Icons.price_change_outlined),
                  label: const Text('تعديل أسعار مجموعة'),
                )),
              ]),
            ),
            Expanded(child: body),
          ],
        ),
        PositionedDirectional(
          end: 16,
          bottom: 88,
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
  final String description;
  final List<OptionGroup> optionGroups;
  const _ProductForm(
    this.name,
    this.price,
    this.image, {
    this.oldPrice,
    this.bestSeller = false,
    this.description = '',
    this.optionGroups = const [],
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
  late final TextEditingController _desc = TextEditingController(
    text: (widget.existing?['description'] ?? '').toString(),
  );
  late List<OptionGroup> _groups = parseOptionGroups(
    widget.existing?['optionGroups'],
  );
  late bool _best = widget.existing?['bestSeller'] == true;
  late String _image = (widget.existing?['image'] ?? '').toString();
  bool _uploading = false;
  String? _error;
  Timer? _draftTimer;
  bool _restoringDraft = false;
  bool _hasDraft = false;

  static String _draftKey(String storeId) =>
      'owner_product_draft_v1_${FirebaseAuth.instance.currentUser?.uid ?? 'guest'}_$storeId';

  static Future<void> clearNewDraft(String storeId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_draftKey(storeId));
  }

  Future<void> _restoreDraft() async {
    if (widget.existing != null) return;
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_draftKey(widget.storeId));
    if (raw == null || !mounted || _name.text.isNotEmpty) return;
    try {
      final saved = jsonDecode(raw);
      if (saved is! Map) return;
      _restoringDraft = true;
      _name.text = (saved['name'] ?? '').toString();
      _price.text = (saved['price'] ?? '').toString();
      _old.text = (saved['oldPrice'] ?? '').toString();
      _desc.text = (saved['description'] ?? '').toString();
      _groups = parseOptionGroups(saved['optionGroups']);
      _best = saved['bestSeller'] == true;
      _image = (saved['image'] ?? '').toString();
      _restoringDraft = false;
      if (mounted) setState(() => _hasDraft = true);
    } catch (_) {
      _restoringDraft = false;
    }
  }

  Future<void> _writeDraft() async {
    if (widget.existing != null) return;
    final raw = jsonEncode({
      'name': _name.text, 'price': _price.text,
      'oldPrice': _old.text, 'description': _desc.text,
      'optionGroups': _groups.map((e) => e.toMap()).toList(),
      'bestSeller': _best, 'image': _image,
    });
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_draftKey(widget.storeId), raw);
    } catch (_) {
      // عدم توفر التخزين المحلي لا يمنع إضافة الصنف أو حفظه في المتجر.
    }
  }

  void _draftChanged() {
    if (widget.existing != null || _restoringDraft) return;
    _draftTimer?.cancel();
    _draftTimer = Timer(const Duration(milliseconds: 300), _writeDraft);
  }

  /// اقتراح تفاصيل من اسم الصنف (قاموس جوه التطبيق، من غير أي قراءة).
  ProductSuggestion? _suggestion;
  String _suggestedFor = '';
  bool _suggestionUsed = false;

  @override
  void initState() {
    super.initState();
    _name.addListener(_updateSuggestion);
    if (widget.existing == null) {
      _name.addListener(_draftChanged);
      _price.addListener(_draftChanged);
      _old.addListener(_draftChanged);
      _desc.addListener(_draftChanged);
      _restoreDraft();
    }
  }

  void _updateSuggestion() {
    final name = _name.text.trim();
    if (name == _suggestedFor) return;
    _suggestedFor = name;
    final next = suggestProduct(name);
    // إعادة بناء مع كل تغيير في الاسم: الاقتراح ومعاينة الصورة التوضيحية.
    setState(() {
      if (next?.description != _suggestion?.description) {
        _suggestion = next;
        _suggestionUsed = false;
      }
    });
  }

  void _applySuggestion() {
    final s = _suggestion;
    if (s == null) return;
    setState(() {
      if (_desc.text.trim().isEmpty) _desc.text = s.description;
      if (_groups.isEmpty && s.optionGroups.isNotEmpty) _groups = s.optionGroups;
      _suggestionUsed = true;
    });
    _draftChanged();
  }

  @override
  void dispose() {
    _draftTimer?.cancel();
    _name.removeListener(_updateSuggestion);
    _name.removeListener(_draftChanged);
    _price.removeListener(_draftChanged);
    _old.removeListener(_draftChanged);
    _desc.removeListener(_draftChanged);
    _name.dispose();
    _price.dispose();
    _old.dispose();
    _desc.dispose();
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
      if (url != null && mounted) {
        setState(() => _image = url);
        _draftChanged();
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'تعذر رفع الصورة. جرّب تاني.');
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _pickSuggestedPhoto() async {
    if (_uploading) return;
    final title = _name.text.trim();
    if (title.length < 2) {
      setState(() => _error = 'اكتب اسم الصنف الأول علشان نبحث عن صورته.');
      return;
    }
    final suggested = await showStockPhotoPicker(context, name: title);
    if (suggested == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final url = await ImageService.uploadSuggestedStockPhoto(
        suggested,
        folder: 'products',
        storeId: widget.storeId,
      );
      if (!mounted) return;
      setState(() => _image = url);
      _draftChanged();
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'تعذر اعتماد الصورة. جرّب صورة أخرى أو ارفع من جهازك.');
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }


  Future<void> _save() async {
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
    // تنبيه «متأكد؟» لو السعر شكله غلط (طماطم 1500 بدل 15)؛ مش منع.
    final previous = widget.existing?['price'];
    final warning = priceWarningFor(
      name,
      price,
      previousPrice: previous is num && previous.toDouble() != price ? previous.toDouble() : null,
    );
    if (warning != null) {
      final ok = await confirmDialog(
        context,
        title: 'راجع السعر',
        message: '$warning\n\nالسعر اللي هيتحفظ: ${formatPrice(price)}',
        confirmLabel: 'السعر صح، احفظ',
      );
      if (!ok || !mounted) return;
    }
    if (!mounted) return;
    _draftTimer?.cancel();
    await _writeDraft();
    if (!mounted) return;
    Navigator.of(context).pop(
      _ProductForm(
        name,
        price,
        _image,
        oldPrice: oldPrice,
        bestSeller: _best,
        description: _desc.text.trim(),
        optionGroups: _groups,
      ),
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
            if (widget.existing == null)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _hasDraft ? 'رجعنالك مسودة الصنف المحفوظة' :
                    'بيتم حفظ مسودة الصنف على الموبايل تلقائيًا',
                  style: TextStyle(color: kMuted, fontSize: 11.5),
                ),
              ),
            if (_suggestion != null && !_suggestionUsed &&
                (_desc.text.trim().isEmpty ||
                    (_groups.isEmpty && _suggestion!.optionGroups.isNotEmpty)))
              _SuggestionCard(
                suggestion: _suggestion!,
                onUse: _applySuggestion,
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
            const SizedBox(height: 12),
            TextField(
              controller: _desc,
              maxLength: 500,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'وصف الصنف (اختياري)',
              ),
            ),
            OutlinedButton.icon(
              onPressed: () async {
                final res = await showOptionGroupsEditor(context, _groups);
                if (res != null && mounted) {
                  setState(() => _groups = res);
                  _draftChanged();
                }
              },
              icon: const Icon(Icons.tune),
              label: Text(
                _groups.isEmpty
                    ? 'خيارات الصنف (سكر، إضافات...)'
                    : 'خيارات الصنف (${_groups.length})',
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _best,
              onChanged: (v) {
                setState(() => _best = v);
                _draftChanged();
              },
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
              )
            else if (_name.text.trim().isNotEmpty)
              // معاينة: لو ما رفعتش صورة، التطبيق بيكمّل بصورة توضيحية من اسم الصنف.
              Column(
                key: const Key('owner-fallback-photo'),
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Image.network(
                      productPhotoFor(name: _name.text).url,
                      height: 90,
                      width: 120,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const SizedBox.shrink(),
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'صورة توضيحية هتظهر للعميل لحد ما ترفع صورة حقيقية',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11.5, color: kMuted),
                  ),
                ],
              ),
            const SizedBox(height: 6),
            FilledButton.tonalIcon(
              key: const Key('owner-upload-photo-button'),
              onPressed: _uploading ? null : _pickImage,
              icon: _uploading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      _image.isEmpty
                          ? Icons.photo_camera_outlined
                          : Icons.sync_rounded,
                    ),
              label: Text(
                _uploading
                    ? 'جاري رفع الصورة...'
                    : _image.isEmpty
                        ? 'ارفع صورة الصنف'
                        : 'تغيير الصورة',
              ),
            ),
            TextButton.icon(
              key: const Key('owner-search-stock-photo'),
              onPressed: _uploading ? null : _pickSuggestedPhoto,
              icon: const Icon(Icons.search_rounded),
              label: const Text('ابحث عن صورة جاهزة للصنف (CC0)'),
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
          child: const Text('إلغاء'),
          onPressed: () async {
            _draftTimer?.cancel();
            await _writeDraft();
            if (context.mounted) Navigator.of(context).pop();
          },
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


/// بوكس «طلب خاص» واضح لصاحب المحل: الوصف + الكمية + الصورة + الصوت.
class _SpecialRequestBox extends StatelessWidget {
  final Map<String, dynamic> data;
  const _SpecialRequestBox({required this.data});

  @override
  Widget build(BuildContext context) {
    final description = (data['description'] ?? '').toString().trim();
    final imageUrl = (data['imageUrl'] ?? '').toString().trim();
    final voiceUrl = (data['voiceUrl'] ?? '').toString().trim();
    final voice = voiceUrl.isNotEmpty ? voiceUrl : (data['voiceBase64'] ?? '').toString().trim();
    final quantity = (data['quantity'] as num?)?.toInt() ?? 1;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: kPrimarySoft,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: kPrimary.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.star_rounded, color: kPrimary, size: 20),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'طلب خاص (من خارج القائمة)',
                  style: TextStyle(
                    color: kPrimary,
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: kPrimary,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  'الكمية × $quantity',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 12.5,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            description.isEmpty ? 'بدون وصف مكتوب (شوف الصورة/الصوت)' : description,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 14.5,
              height: 1.5,
            ),
          ),
          if (imageUrl.isNotEmpty) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.network(
                imageUrl,
                height: 160,
                width: double.infinity,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) =>
                    const Text('تعذر عرض الصورة المرفقة'),
              ),
            ),
          ],
          if (voice.isNotEmpty) ...[
            const SizedBox(height: 8),
            _SpecialVoicePlayer(encoded: voice),
          ],
        ],
      ),
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
      // الطلبات الجديدة: رابط Cloudinary. القديمة: base64 جوه الطلب.
      await _player.setSource(widget.encoded.startsWith('https://')
          ? audio.UrlSource(widget.encoded)
          : audio.BytesSource(base64Decode(widget.encoded)));
      await _player.resume();
      if (mounted) setState(() => _playing = true);
    } catch (_) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          appSnack('تعذر تشغيل الرسالة الصوتية.'),
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


/// رسوم خدمة وصّلي على المحل: المستحق والمدفوع والمتبقي (من كل الطلبات المسلّمة).
class StoreFeeSummaryView extends StatefulWidget {
  final String storeId;

  /// لو اتبعت، بنستخدمه بدل قراءة جديدة (عشان الصفحة اللي فوق ما تقراش مرتين).
  final Future<StoreFeeSummary>? future;
  const StoreFeeSummaryView({super.key, required this.storeId, this.future});

  @override
  State<StoreFeeSummaryView> createState() => _StoreFeeSummaryViewState();
}

class _StoreFeeSummaryViewState extends State<StoreFeeSummaryView> {
  late Future<StoreFeeSummary> _future = widget.future ?? StoreFeeService.load(widget.storeId);

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<StoreFeeSummary>(
      future: _future,
      builder: (context, snap) {
        if (snap.hasError) {
          return Row(children: [
            const Expanded(child: Text('تعذر تحميل رسوم وصّلي.', style: TextStyle(fontSize: 12.5))),
            TextButton(
              onPressed: () => setState(() => _future = StoreFeeService.load(widget.storeId)),
              child: const Text('حاول تاني'),
            ),
          ]);
        }
        final s = snap.data;
        if (s == null) return const LinearProgressIndicator(minHeight: 2);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('رسوم خدمة وصّلي', style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            Text('المستحقة على المحل: ${formatPrice(s.due)}'),
            Text('المدفوعة: ${formatPrice(s.paid)}'),
            Text(
              'المتبقي: ${formatPrice(s.outstanding)}',
              style: TextStyle(
                fontWeight: FontWeight.w800,
                color: s.outstandingMinor > 0 ? kDanger : kSuccess,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'العميل بيدفع رسوم الخدمة (2%، من 5 لـ15 جنيه) ضمن إجمالي الطلب، فالمحل بيستلمها ويوردها لوصّلي.',
              style: TextStyle(fontSize: 12),
            ),
          ],
        );
      },
    );
  }
}

/// كارت «اقتراح تلقائي» تحت اسم الصنف. ما بيحفظش حاجة غير لما صاحب المحل يدوس «استخدم».
class _SuggestionCard extends StatelessWidget {
  final ProductSuggestion suggestion;
  final VoidCallback onUse;
  const _SuggestionCard({required this.suggestion, required this.onUse});

  @override
  Widget build(BuildContext context) {
    final options = suggestion.optionGroups.map((g) => g.title).join('، ');
    return Container(
      key: const Key('product-autofill-card'),
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 4, 8),
      decoration: BoxDecoration(
        color: kAccent.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kAccent.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(Icons.auto_awesome_rounded, size: 18, color: kAccent),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${suggestion.section} • بال${suggestion.unit}',
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                ),
                Text(
                  options.isEmpty
                      ? suggestion.description
                      : '${suggestion.description} + خيارات: $options',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
              ],
            ),
          ),
          TextButton(
            key: const Key('product-autofill-use'),
            onPressed: onUse,
            child: const Text('استخدم'),
          ),
        ],
      ),
    );
  }
}

/// لصق قايمة أصناف ← جدول مراجعة ← «إضافة الكل». مفيش أي قراءة من Firestore هنا.
class _BulkProductsSheet extends StatefulWidget {
  const _BulkProductsSheet();

  @override
  State<_BulkProductsSheet> createState() => _BulkProductsSheetState();
}

class _BulkProductsSheetState extends State<_BulkProductsSheet> {
  final _text = TextEditingController();
  BulkParseResult? _result;
  final Set<int> _off = {};

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _parse() {
    final r = parseBulkProducts(_text.text);
    setState(() {
      _result = r;
      _off.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    final r = _result;
    final chosen = r == null
        ? const <BulkProductLine>[]
        : [for (var i = 0; i < r.lines.length; i++) if (!_off.contains(i)) r.lines[i]];
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.88),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    r == null ? 'الصق قايمة أصنافك' : 'راجع الأصناف قبل الإضافة',
                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    r == null
                        ? 'سطر لكل صنف: الاسم والسعر. مثال:\nطماطم 15\nخيار 10\nجبنة رومي 250'
                        : 'الوصف بيتكتب لوحده لو الصنف معروف. شيل العلامة من أي صنف مش عايزه.',
                    style: TextStyle(fontSize: 12.5, color: kMuted, height: 1.5),
                  ),
                  const SizedBox(height: 10),
                  if (r == null)
                    Flexible(
                      child: TextField(
                        key: const Key('bulk-text'),
                        controller: _text,
                        onChanged: (_) => setState(() {}),
                        minLines: 6,
                        maxLines: 14,
                        decoration: const InputDecoration(hintText: 'طماطم 15\nخيار 10'),
                      ),
                    )
                  else
                    Flexible(
                      child: ListView(
                        shrinkWrap: true,
                        children: [
                          for (var i = 0; i < r.lines.length; i++)
                            CheckboxListTile(
                              key: Key('bulk-line-$i'),
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: !_off.contains(i),
                              onChanged: (v) => setState(() => v == true ? _off.remove(i) : _off.add(i)),
                              title: Text(
                                '${r.lines[i].name} — ${formatPrice(r.lines[i].price)}',
                                style: const TextStyle(fontWeight: FontWeight.w700),
                              ),
                              subtitle: Text(
                                r.lines[i].priceWarning ??
                                    (r.lines[i].description.isEmpty
                                        ? 'من غير وصف (تقدر تضيفه بعدين)'
                                        : r.lines[i].description),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: r.lines[i].priceWarning != null ? kDanger : kMuted,
                                  fontWeight: r.lines[i].priceWarning != null ? FontWeight.w700 : null,
                                ),
                              ),
                            ),
                          if (r.skipped.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                'سطور ما اتفهمتش (${r.skipped.length}): ${r.skipped.take(5).join('، ')}'
                                '${r.skipped.length > 5 ? '…' : ''}',
                                style: TextStyle(fontSize: 12, color: kMuted),
                              ),
                            ),
                        ],
                      ),
                    ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      if (r != null)
                        TextButton(
                          onPressed: () => setState(() => _result = null),
                          child: const Text('رجوع للتعديل'),
                        ),
                      const Spacer(),
                      FilledButton(
                        key: const Key('bulk-confirm'),
                        onPressed: r == null
                            ? (_text.text.trim().isEmpty ? null : _parse)
                            : (chosen.isEmpty ? null : () => Navigator.pop(context, chosen)),
                        child: Text(r == null ? 'تجهيز' : 'إضافة ${chosen.length} صنف'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «النهارده: 12 طلب • اتسلّم 9 • 1,800 ج.م» من الطلبات اللي ظاهرة أصلًا (صفر قراءات).
/// سطر واحد مضغوط عشان ما يزقّش أزرار الطلبات لتحت.
class _TodaySummaryBar extends StatelessWidget {
  final List<AppOrder> orders;
  const _TodaySummaryBar({required this.orders});

  @override
  Widget build(BuildContext context) {
    final s = StoreTodaySummary.of(orders, DateTime.now());
    if (s.isEmpty) return const SizedBox.shrink();
    final parts = <String>[
      '${s.orders} طلب',
      'اتسلّم ${s.delivered}',
      formatPrice(s.deliveredGoods),
      if (s.cancelled > 0) 'ملغي ${s.cancelled}',
    ];
    return Container(
      key: const Key('owner-today-summary'),
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 2),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      decoration: BoxDecoration(
        color: kPrimary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        children: [
          Icon(Icons.today_rounded, size: 16, color: kPrimary),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              'النهارده: ${parts.join(' • ')}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }
}


/// قائمة قوالب محلية، تُراجع الأسعار قبل أي كتابة. لا نضع أسعار تخمينية.
class _ProductTemplatesSheet extends StatefulWidget {
  const _ProductTemplatesSheet();

  @override
  State<_ProductTemplatesSheet> createState() => _ProductTemplatesSheetState();
}

class _ProductTemplatesSheetState extends State<_ProductTemplatesSheet> {
  StoreTemplate _template = storeProductTemplates.first;
  final Set<String> _chosen = {};
  final Map<String, TextEditingController> _prices = {};
  String? _error;

  TextEditingController _controller(String name) =>
      _prices.putIfAbsent(name, () => TextEditingController());

  @override
  void dispose() {
    for (final c in _prices.values) { c.dispose(); }
    super.dispose();
  }

  void _done() {
    if (_chosen.isEmpty) {
      setState(() => _error = 'اختار صنف واحد على الأقل.');
      return;
    }
    final lines = <BulkProductLine>[];
    for (final name in _template.products) {
      if (!_chosen.contains(name)) continue;
      final price = double.tryParse(
          _controller(name).text.trim().replaceAll(',', '.'));
      if (price == null || price <= 0 || price > 20000) {
        setState(() => _error =
            'اكتب سعرًا صحيحًا لكل صنف مختار (من 1 إلى 20000 جنيه).');
        return;
      }
      final s = suggestProduct(name);
      lines.add(BulkProductLine(name, price,
          suggestion: s, priceWarning: priceWarningFor(name, price)));
    }
    Navigator.pop(context, lines);
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: SafeArea(
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: FractionallySizedBox(
            heightFactor: .88,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text('جهّز محلك بأصناف جاهزة',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 4),
                  const Text('اختار اللي بتبيعه واكتب سعره بنفسك. '
                      'مش هنضيف أي صنف إلا بعد تأكيدك.',
                      style: TextStyle(fontSize: 12.5)),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<StoreTemplate>(
                    key: const Key('template-category'),
                    value: _template,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'نوع المحل'),
                    items: [
                      for (final t in storeProductTemplates)
                        DropdownMenuItem(value: t, child: Text(t.label)),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _template = value; _chosen.clear(); _error = null;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _template.products.length,
                      itemBuilder: (context, index) {
                        final name = _template.products[index];
                        return Row(children: [
                          Checkbox(
                            value: _chosen.contains(name),
                            onChanged: (value) => setState(() {
                              if (value == true) { _chosen.add(name); }
                              else { _chosen.remove(name); }
                              _error = null;
                            }),
                          ),
                          Expanded(child: Text(name, maxLines: 2,
                              overflow: TextOverflow.ellipsis)),
                          SizedBox(
                            width: 94,
                            child: TextField(
                              key: Key('template-price-$index'),
                              controller: _controller(name),
                              enabled: _chosen.contains(name),
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              decoration: const InputDecoration(
                                labelText: 'السعر', suffixText: 'ج',
                                isDense: true,
                              ),
                            ),
                          ),
                        ]);
                      },
                    ),
                  ),
                  if (_error != null)
                    Text(_error!, style: TextStyle(color: kDanger)),
                  const SizedBox(height: 6),
                  Row(children: [
                    TextButton(onPressed: () => Navigator.pop(context),
                        child: const Text('إلغاء')),
                    const Spacer(),
                    FilledButton.icon(
                      key: const Key('template-add-selected'),
                      onPressed: _done,
                      icon: const Icon(Icons.check),
                      label: Text('مراجعة وإضافة (${_chosen.length})'),
                    ),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
