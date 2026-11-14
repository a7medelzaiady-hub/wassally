import 'dart:async';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';

import '../models/store.dart';
import '../services/cart_model.dart';
import '../services/catalog_service.dart';
import '../services/navigation.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import '../theme/brand.dart';
import '../widgets/category_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/glossy_fab.dart';
import 'offers_page.dart';
import '../widgets/promo_banners.dart';
import 'categories_landing_page.dart' show kCategoryPhotos;
import 'notifications_page.dart';
import 'store_page.dart';

/// المحل + بياناته الخام (للصورة والتقييم ومدة التوصيل).
class _StoreItem {
  final Store store;
  final Map<String, dynamic> data;
  const _StoreItem(this.store, this.data);

  // الحقل الجديد imageUrl (لوحة الأدمن) مع الرجوع للقديم image.
  String get image => (data['imageUrl'] ?? data['image'] ?? '').toString();
  String get time => (data['time'] ?? '').toString();
  double get rating {
    final n = (data['ratingCount'] as num?)?.toInt() ?? 0;
    if (n > 0) return ((data['ratingSum'] as num?)?.toDouble() ?? 0) / n;
    return (data['rating'] as num?)?.toDouble() ?? 0;
  }
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  String? _category;
  String _query = '';
  final TextEditingController _searchCtrl = TextEditingController();

  // العنوان المحفوظ للعميل.
  String _address = '';

  // الإشعارات.
  StreamSubscription<RemoteMessage>? _msgSub;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _unreadStream;

  // الجرس: أنيميشن الهز + الصوت.
  late final AnimationController _bellCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  final AudioPlayer _player = AudioPlayer();

  /// آخر عدد إشعارات غير مقروءة. -1 = لسه ما قرينا أول قيمة.
  int _lastUnread = -1;

  // المحلات بتتحمّل مرة واحدة (من الكاش لو الكتالوج ما اتغيرش) بدل stream دايم.
  Future<QuerySnapshot<Map<String, dynamic>>> _storesFuture = _loadStores();

  static Future<QuerySnapshot<Map<String, dynamic>>> _loadStores() =>
      CatalogService.get(
        FirebaseFirestore.instance.collection('stores'),
        'stores',
      );

  @override
  void initState() {
    super.initState();

    // القسم اللي العميل اختاره من شاشة الأقسام بعد الدخول.
    final req = homeCategoryRequest.value;
    if (req != null) {
      _category = req;
      homeCategoryRequest.value = null;
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _unreadStream = FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots();
    }

    _loadSavedAddress();
    _initNotifications();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    _msgSub?.cancel();
    _searchCtrl.dispose();
    _bellCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _storesFuture = _loadStores();
    });
  }

  void _openStore(Store s) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => StorePage(store: s)));
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ───────────────────────── الموقع ─────────────────────────

  Future<void> _loadSavedAddress() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final a = (doc.data()?['address'] ?? '').toString();
      if (mounted && a.isNotEmpty) setState(() => _address = a);
    } catch (e) {
      debugPrint('Load address error: $e');
    }
  }

  Future<void> _saveAddress(String address, {double? lat, double? lng}) async {
    if (mounted) setState(() => _address = address);
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'address': address,
        'lat': ?lat,
        'lng': ?lng,
      }, SetOptions(merge: true));
      _toast('تم حفظ موقعك');
    } catch (e) {
      debugPrint('Save address error: $e');
      _toast('تعذر حفظ العنوان');
    }
  }

  /// شرح واضح قبل طلب إذن الموقع (متطلب سياسة جوجل بلاي: طلب الإذن في سياقه).
  Future<bool> _confirmLocationUse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'استخدام موقعك',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
          content: const Text(
            'هنستخدم موقع جهازك مرة واحدة بس عشان نحدد عنوان التوصيل، '
            'ونحفظ العنوان في حسابك لتسهيل طلباتك الجاية. '
            'مش بنتتبع موقعك في الخلفية، وتقدر تكتب عنوانك بنفسك بدل كده.',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('اكتب العنوان بنفسي'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('متابعة'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  Future<void> _useGps() async {
    if (!await _confirmLocationUse() || !mounted) return;
    _toast('جاري تحديد موقعك...');
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        _toast('فعّل خدمة الموقع (GPS) من الإعدادات');
        await Geolocator.openLocationSettings();
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied) {
        _toast('محتاجين إذن الموقع عشان نحدد مكانك');
        return;
      }
      if (perm == LocationPermission.deniedForever) {
        _toast('إذن الموقع مرفوض. فعّله من إعدادات التطبيق');
        await Geolocator.openAppSettings();
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      var text =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final marks = await placemarkFromCoordinates(
          pos.latitude,
          pos.longitude,
        );
        if (marks.isNotEmpty) {
          final m = marks.first;
          final parts = [
            m.street,
            m.subLocality,
            m.locality,
            m.administrativeArea,
          ].where((e) => e != null && e.trim().isNotEmpty).toList();
          if (parts.isNotEmpty) text = parts.join('، ');
        }
      } catch (e) {
        debugPrint('Reverse geocoding error: $e');
      }

      await _saveAddress(text, lat: pos.latitude, lng: pos.longitude);
    } catch (e) {
      debugPrint('GPS error: $e');
      _toast('تعذر تحديد الموقع، جرّب تاني أو اكتب العنوان بنفسك');
    }
  }

  void _pickLocation() {
    final ctrl = TextEditingController(text: _address);
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          20,
          20,
          MediaQuery.viewInsetsOf(ctx).bottom + 20,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'اختر موقع التوصيل',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.w800,
                color: Brand.ink,
              ),
            ),
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: () {
                Navigator.of(ctx).pop();
                _useGps();
              },
              icon: const Icon(Icons.my_location_rounded),
              label: const Text('استخدم موقعي الحالي'),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: ctrl,
              maxLines: 2,
              decoration: InputDecoration(
                hintText: 'أو اكتب عنوانك (الحي، الشارع، علامة مميزة)',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
            const SizedBox(height: 10),
            OutlinedButton(
              onPressed: () {
                final t = ctrl.text.trim();
                if (t.isEmpty) return;
                Navigator.of(ctx).pop();
                _saveAddress(t);
              },
              child: const Text('حفظ العنوان'),
            ),
          ],
        ),
      ),
    ).whenComplete(ctrl.dispose);
  }

  // ───────────────────────── الإشعارات ─────────────────────────

  Future<void> _initNotifications() async {
    try {
      final fm = FirebaseMessaging.instance;
      final settings = await fm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) return;

      // اشتراك عام: تقدر تبعت لكل العملاء من Firebase Console على topic اسمه all.
      await fm.subscribeToTopic('all');

      // تسجيل توكن الجهاز بيتم في NotificationService (users/{uid}.fcmTokens)،
      // فمش بنكرره هنا.

      // الإشعار وإنت فاتح التطبيق.
      // ملاحظة: الجرس بيرن من الـ StreamBuilder في _bell() عند زيادة العدد،
      // فمفيش حاجة هنا عشان ما يرنش مرتين.
      _msgSub = FirebaseMessaging.onMessage.listen((m) {
        final n = m.notification;
        if (n == null || !mounted) return;
        final text = [
          n.title,
          n.body,
        ].where((e) => e != null && e.trim().isNotEmpty).join('\n');
        if (text.isEmpty) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(text),
              duration: const Duration(seconds: 5),
              action: SnackBarAction(
                label: 'عرض',
                onPressed: _openNotifications,
              ),
            ),
          );
      });
    } catch (e) {
      debugPrint('Notifications init error: $e');
    }
  }

  void _openNotifications() {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
  }

  /// هزة الجرس + اهتزاز خفيف + صوت.
  Future<void> _ringBell({bool withSound = true}) async {
    if (!mounted) return;
    _bellCtrl.forward(from: 0);
    if (!withSound) return;
    HapticFeedback.mediumImpact();
    try {
      await _player.stop();
      await _player.play(AssetSource('sounds/bell.wav'));
    } catch (e) {
      debugPrint('Bell sound error: $e');
    }
  }

  /// بتتنادى مع كل تحديث لعدد الإشعارات غير المقروءة.
  void _onUnreadChanged(int n) {
    final prev = _lastUnread;
    _lastUnread = n;
    if (prev == -1) {
      // أول قراءة: هزة تعريفية بدون صوت لو في إشعارات.
      if (n > 0) {
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _ringBell(withSound: false),
        );
      }
      return;
    }
    if (n > prev) {
      // إشعار جديد وصل: هز + صوت.
      WidgetsBinding.instance.addPostFrameCallback((_) => _ringBell());
    }
  }

  Widget _bell() {
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Material(
          color: Colors.white,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: _openNotifications,
            child: SizedBox(
              width: 42,
              height: 42,
              child: AnimatedBuilder(
                animation: _bellCtrl,
                builder: (context, child) {
                  // هزة يمين وشمال وتخفت تدريجيًا
                  final t = _bellCtrl.value;
                  final angle = math.sin(t * math.pi * 6) * 0.35 * (1 - t);
                  return Transform.rotate(
                    angle: angle,
                    alignment: Alignment.topCenter,
                    child: child,
                  );
                },
                child: Icon(
                  Icons.notifications_none_rounded,
                  color: Brand.green,
                  size: 24,
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: -5,
          left: -5,
          child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _unreadStream,
            builder: (context, snap) {
              if (snap.hasData) _onUnreadChanged(snap.data!.docs.length);
              final n = snap.data?.docs.length ?? 0;
              if (n == 0) return const SizedBox.shrink();
              return Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Colors.red,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white, width: 1.5),
                ),
                child: Text(
                  n > 9 ? '9+' : '$n',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────────────────────── الهيدر ─────────────────────────

  /// زر السلة (شنطة) بعدّاد، زي هيدر طلبات.
  Widget _cartButton() {
    return ListenableBuilder(
      listenable: cart,
      builder: (context, _) {
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Material(
              color: Colors.white,
              shape: const CircleBorder(),
              child: InkWell(
                customBorder: const CircleBorder(),
                onTap: () => shellTab.value = 1,
                child: SizedBox(
                  width: 42,
                  height: 42,
                  child: Icon(
                    Icons.shopping_bag_outlined,
                    color: Brand.ink,
                    size: 22,
                  ),
                ),
              ),
            ),
            if (cart.count > 0)
              PositionedDirectional(
                bottom: -4,
                start: -4,
                child: Container(
                  constraints: const BoxConstraints(
                    minWidth: 20,
                    minHeight: 20,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: Brand.greenDark,
                    shape: cart.count > 9
                        ? BoxShape.rectangle
                        : BoxShape.circle,
                    borderRadius: cart.count > 9
                        ? BorderRadius.circular(10)
                        : null,
                    border: Border.all(color: Colors.white, width: 1.5),
                  ),
                  child: Text(
                    cart.count > 99 ? '99+' : '${cart.count}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  /// أيقونة زخرفية غامقة شفافة في خلفية الهيدر.
  Widget _bgIcon(IconData icon, double size, double angle) => Transform.rotate(
    angle: angle,
    child: Icon(
      icon,
      size: size,
      color: Brand.greenDark.withValues(alpha: 0.28),
    ),
  );

  /// الهيدر زي طلبات: لون واحد، "التوصيل إلى" فوق على جنب والسلة على الجنب التاني،
  /// وشريط البحث جوّه الهيدر نفسه، وحافة سفلية متموّجة.
  Widget _header() {
    final top = MediaQuery.paddingOf(context).top;
    return ClipPath(
      clipper: _WaveClipper(),
      child: Container(
        color: Brand.green,
        child: Stack(
          children: [
            PositionedDirectional(
              top: top + 2,
              start: 70,
              child: _bgIcon(Icons.local_florist_rounded, 78, -0.4),
            ),
            PositionedDirectional(
              top: top - 6,
              start: 176,
              child: _bgIcon(Icons.redeem_rounded, 96, 0.1),
            ),
            PositionedDirectional(
              top: top + 8,
              end: 24,
              child: _bgIcon(Icons.sports_esports_rounded, 84, 0.25),
            ),
            PositionedDirectional(
              bottom: 10,
              start: -14,
              child: _bgIcon(Icons.fastfood_rounded, 70, 0.3),
            ),
            Padding(
              padding: EdgeInsets.fromLTRB(16, top + 10, 16, 30),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _pickLocation,
                          child: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  _address.isEmpty
                                      ? 'التوصيل إلى: اختر الموقع'
                                      : 'التوصيل إلى $_address',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(
                                Icons.keyboard_arrow_down_rounded,
                                color: Colors.white,
                                size: 24,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      _bell(),
                      const SizedBox(width: 10),
                      _cartButton(),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _searchBar(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      height: 50,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: Colors.grey.shade300, width: 1),
      ),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (v) => setState(() => _query = v.trim()),
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'ابحث عن مطعم أو محل هنا ...',
          hintStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.grey),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  // ───────────────────────── الأقسام ─────────────────────────

  Widget _categoriesRow(Map<String, String> categoryImages) {
    final tiles = <CategoryInfo>[kAllCategory, ...kCategories];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: LayoutBuilder(
        builder: (context, c) {
          const gap = 10.0;
          final w = (c.maxWidth - gap * 3) / 4;
          return Wrap(
            spacing: gap,
            runSpacing: gap,
            children: [
              for (final info in tiles)
                SizedBox(
                  width: w,
                  height: 104,
                  child: _CategoryTile(
                    label: info.category,
                    imageUrl: info.category == 'الكل'
                        ? ''
                        : (kCategoryPhotos[info.category] ??
                              categoryImages[info.category] ??
                              ''),
                    isAll: info.category == 'الكل',
                    selected: info.category == 'الكل'
                        ? _category == null
                        : _category == info.category,
                    onTap: () => setState(() {
                      if (info.category == 'الكل' ||
                          _category == info.category) {
                        _category = null;
                      } else {
                        _category = info.category;
                      }
                    }),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ───────────────────────── تحليل البيانات ─────────────────────────

  ({List<_StoreItem> stores, Map<String, String> categoryImages}) _parse(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) {
    final stores = <_StoreItem>[];
    final categoryImages = <String, String>{};
    for (final doc in snap.docs) {
      try {
        final data = doc.data();
        final store = Store.fromMap(doc.id, data);

        if (!store.active) continue;
        final item = _StoreItem(store, data);
        stores.add(item);
        if (store.category.isNotEmpty && item.image.isNotEmpty) {
          categoryImages.putIfAbsent(store.category, () => item.image);
        }
      } catch (e) {
        debugPrint('Error parsing store document ${doc.id}: $e');
      }
    }
    stores.sort((a, b) => a.store.order.compareTo(b.store.order));
    return (stores: stores, categoryImages: categoryImages);
  }

  // ───────────────────────── عروض / الأكثر مبيعًا ─────────────────────────

  Widget _highlights(List<_StoreItem> all) {
    final offers = <(_StoreItem, Map<String, dynamic>)>[];
    final best = <(_StoreItem, Map<String, dynamic>)>[];
    for (final s in all) {
      if (s.data['active'] == false) continue;
      for (final k in ['offerItems', 'bestItems']) {
        final raw = s.data[k];
        if (raw is! List) continue;
        for (final e in raw) {
          if (e is! Map) continue;
          final m = Map<String, dynamic>.from(e);
          (k == 'offerItems' ? offers : best).add((s, m));
        }
      }
    }
    if (offers.isEmpty && best.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (offers.isNotEmpty) _hlRow('عروض', offers, offer: true),
          if (best.isNotEmpty) _hlRow('الأكثر مبيعًا', best),
        ],
      ),
    );
  }

  Widget _hlRow(
    String title,
    List<(_StoreItem, Map<String, dynamic>)> items, {
    bool offer = false,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
          child: Text(
            title,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: Brand.ink,
            ),
          ),
        ),
        SizedBox(
          height: 176,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length > 12 ? 12 : items.length,
            separatorBuilder: (_, _) => const SizedBox(width: 10),
            itemBuilder: (_, i) {
              final (s, m) = items[i];
              final price = (m['price'] as num?)?.toDouble() ?? 0;
              final old = (m['oldPrice'] as num?)?.toDouble() ?? 0;
              final img = (m['image'] ?? '').toString();
              return GestureDetector(
                onTap: () => _openStore(s.store),
                child: Container(
                  width: 128,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: kLine),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            img.isEmpty
                                ? Container(
                                    decoration: BoxDecoration(
                                      gradient: Brand.softGradient,
                                    ),
                                  )
                                : Image.network(
                                    thumb(img, w: 300),
                                    fit: BoxFit.cover,
                                    errorBuilder: (_, _, _) => Container(
                                      decoration: BoxDecoration(
                                        gradient: Brand.softGradient,
                                      ),
                                    ),
                                  ),
                            if (offer && old > price && old > 0)
                              Positioned(
                                top: 6,
                                right: 6,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kDanger,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    '${((1 - price / old) * 100).round()}%-',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              (m['name'] ?? '').toString(),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w800,
                                color: Brand.ink,
                              ),
                            ),
                            Text(
                              s.store.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11, color: kMuted),
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Text(
                                  formatPrice(price),
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w900,
                                    color: Brand.goldDeep,
                                  ),
                                ),
                                if (offer && old > price) ...[
                                  const SizedBox(width: 5),
                                  Text(
                                    formatPrice(old),
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      color: kMuted,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.white,
      child: FutureBuilder<QuerySnapshot<Map<String, dynamic>>>(
        future: _storesFuture,
        builder: (context, snapshot) {
          final loading = !snapshot.hasData && !snapshot.hasError;
          final hasError = snapshot.hasError && !snapshot.hasData;
          if (snapshot.hasError) {
            debugPrint('Firestore Error Details: ${snapshot.error}');
          }

          final parsed = snapshot.hasData
              ? _parse(snapshot.data!)
              : (stores: <_StoreItem>[], categoryImages: <String, String>{});
          final all = parsed.stores;
          final q = _query.toLowerCase();
          final filtered = all.where((s) {
            final okCategory =
                _category == null || s.store.category == _category;
            final okQuery = q.isEmpty || s.store.name.toLowerCase().contains(q);
            return okCategory && okQuery;
          }).toList();

          final showBanner = _query.isEmpty && _category == null;

          final scroll = CustomScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _header()),

              // الأقسام المتاحة أعلى الصفحة (الكل، مطاعم، سوبرماركت، ورد).
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.only(top: 14, bottom: 2),
                  child: _categoriesRow(parsed.categoryImages),
                ),
              ),

              // البانر في النص (تحت الأقسام)
              if (showBanner)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.only(top: 14),
                    child: PromoBanners(),
                  ),
                ),

              if (showBanner && !loading && !hasError)
                SliverToBoxAdapter(child: _highlights(all)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _category ?? 'المحلات',
                          style: TextStyle(
                            fontSize: 19,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
                          ),
                        ),
                      ),
                      if (!loading && !hasError)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: Brand.gold.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${filtered.length} محل',
                            style: TextStyle(
                              color: Brand.goldDeep,
                              fontWeight: FontWeight.w800,
                              fontSize: 12.5,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),

              if (loading)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 40),
                    child: Center(
                      child: CircularProgressIndicator(color: Brand.green),
                    ),
                  ),
                )
              else if (hasError)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Column(
                      children: [
                        const EmptyState(
                          icon: Icons.cloud_off,
                          title: 'حصل خطأ في تحميل المحلات',
                          message: 'تأكد من الاتصال بالإنترنت وحاول تاني.',
                        ),
                        TextButton.icon(
                          onPressed: _retry,
                          icon: const Icon(Icons.refresh),
                          label: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  ),
                )
              else if (filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: EmptyState(
                      icon: all.isEmpty ? Icons.storefront : Icons.search_off,
                      title: all.isEmpty
                          ? 'لسه مفيش محلات'
                          : 'مفيش نتائج مطابقة',
                      message: all.isEmpty
                          ? 'المحلات هتظهر هنا أول ما تتضاف.'
                          : 'جرّب كلمة تانية أو اختار قسم مختلف.',
                    ),
                  ),
                )
              else
                // كارتين جنب بعض بمسافات صغيرة وصور كبيرة
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 24),
                  sliver: SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 0.76,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, i) => _StoreGridCard(
                        item: filtered[i],
                        onTap: () => _openStore(filtered[i].store),
                      ),
                      childCount: filtered.length,
                    ),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 84)),
            ],
          );

          return Stack(children: [scroll, PositionedDirectional(end: 18, bottom: 18, child: GlossyFab(icon: Icons.local_offer_rounded, tooltip: 'عروض وخصومات', onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const OffersPage())))]),);
        },
      ),
    );
  }
}

/// كارت المحل: بيصغر ويلمع إطاره ذهبي لما تلمسه.
class _StoreGridCard extends StatefulWidget {
  final _StoreItem item;
  final VoidCallback onTap;
  const _StoreGridCard({required this.item, required this.onTap});

  @override
  State<_StoreGridCard> createState() => _StoreGridCardState();
}

class _StoreGridCardState extends State<_StoreGridCard> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  Widget _fallback() => Container(
    decoration: BoxDecoration(gradient: Brand.softGradient),
    child: Center(
      child: Text(
        widget.item.store.name.isEmpty
            ? ''
            : widget.item.store.name.substring(0, 1),
        style: TextStyle(
          color: Brand.gold,
          fontSize: 38,
          fontWeight: FontWeight.w900,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    return GestureDetector(
      onTapDown: (_) => _set(true),
      onTapUp: (_) => _set(false),
      onTapCancel: () => _set(false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: _down ? Brand.gold : Colors.transparent,
              width: 2,
            ),
            boxShadow: [
              BoxShadow(
                color: (_down ? Brand.green : Colors.black).withValues(
                  alpha: _down ? 0.30 : 0.07,
                ),
                blurRadius: _down ? 16 : 8,
                offset: Offset(0, _down ? 6 : 3),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // الصورة بتملا الجزء العلوي كله
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    item.image.isEmpty
                        ? _fallback()
                        : Image.network(
                            thumb(item.image),
                            fit: BoxFit.cover,
                            loadingBuilder: (context, child, progress) =>
                                progress == null ? child : _fallback(),
                            errorBuilder: (_, _, _) => _fallback(),
                          ),
                    if (item.rating > 0)
                      Positioned(
                        top: 6,
                        left: 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.94),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.star_rounded,
                                size: 14,
                                color: Brand.gold,
                              ),
                              const SizedBox(width: 2),
                              Text(
                                item.rating.toStringAsFixed(1),
                                style: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: Brand.ink,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // اسم المحل: الخط بيصغر تلقائيًا حسب طول الاسم
                    // لحد ما يظهر كامل في سطر واحد.
                    SizedBox(
                      width: double.infinity,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: AlignmentDirectional.centerStart,
                        child: Text(
                          item.store.name,
                          maxLines: 1,
                          softWrap: false,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            item.store.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Colors.grey.shade600,
                            ),
                          ),
                        ),
                        if (item.time.isNotEmpty) ...[
                          Icon(
                            Icons.schedule_rounded,
                            size: 13,
                            color: Brand.goldDeep,
                          ),
                          const SizedBox(width: 2),
                          Text(
                            item.time,
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Brand.green,
                            ),
                          ),
                        ],
                      ],
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

/// حافة سفلية متموّجة للهيدر.
class _WaveClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const amp = 6.0;
    final base = size.height - amp * 2;
    final p = Path()
      ..moveTo(0, 0)
      ..lineTo(0, base);
    for (double x = 0; x <= size.width; x += 4) {
      p.lineTo(x, base + amp + amp * math.sin(x / size.width * math.pi * 14));
    }
    p
      ..lineTo(size.width, 0)
      ..close();
    return p;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}

/// مربع قسم بصورة حقيقية على خلفية بيج، زي تطبيقات التوصيل الكبيرة.
class _CategoryTile extends StatelessWidget {
  final String label;
  final String imageUrl;
  final bool isAll;
  final bool selected;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.label,
    required this.imageUrl,
    required this.isAll,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          color: kTileBeige,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? Brand.green : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: SizedBox(
                width: 62,
                height: 62,
                child: isAll || imageUrl.isEmpty
                    ? Container(
                        decoration: BoxDecoration(gradient: Brand.softGradient),
                        child: Icon(
                          Icons.grid_view_rounded,
                          color: Brand.green,
                          size: 28,
                        ),
                      )
                    : Image.network(
                        thumb(imageUrl, w: 200),
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => Container(
                          decoration: BoxDecoration(
                            gradient: Brand.softGradient,
                          ),
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w800,
                color: selected ? Brand.green : Brand.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
