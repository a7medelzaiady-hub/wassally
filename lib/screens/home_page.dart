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
import 'package:shared_preferences/shared_preferences.dart';

import '../models/app_role.dart';
import '../models/store.dart';
import '../models/product_offer.dart';
import '../services/catalog_service.dart';
import '../services/read_meter.dart';
import '../services/catalog_sync.dart';
import '../services/navigation.dart';
import '../services/notification_service.dart';
import '../services/performance_monitor.dart';
import '../services/role_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import '../theme/brand.dart';
import '../widgets/promo_banners.dart';
import '../widgets/home_category_grid.dart';
import 'notifications_page.dart';
import 'quick_order_create_page.dart';
import 'store_page.dart';
import 'store_directory_page.dart';
import '../widgets/closed_badge.dart';
import '../widgets/cached_net_image.dart';

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
  const HomePage({super.key, this.offersOnly = false});

  final bool offersOnly;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  // العنوان المحفوظ للعميل.
  String _address = '';


  // الإشعارات.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _unreadStream;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _courierStatusSubscription;

  // الجرس: أنيميشن الهز + الصوت.
  late final AnimationController _bellCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  final AudioPlayer _player = AudioPlayer();

  /// آخر عدد إشعارات غير مقروءة. -1 = لسه ما قرينا أول قيمة.
  int _lastUnread = -1;

  // المحلات بتتحمّل مرة واحدة (من الكاش لو الكتالوج ما اتغيرش) بدل stream دايم.
  // الفهرس المجمّع = قراءة واحدة لكل المحلات؛ لو مش جاهز بنرجع للاستعلام القديم بنفس الكاش.
  Future<List<CatalogDoc>> _storesFuture = _loadStores();
  Future<List<(_StoreItem, Map<String, dynamic>)>>? _offersFuture;

  static Future<List<CatalogDoc>> _loadStores() => CatalogReader.activeStores(
        () => CatalogService.get(
          FirebaseFirestore.instance
              .collection('stores')
              .where('active', isEqualTo: true),
          'stores_active',
        ),
      );

  @override
  void initState() {
    super.initState();
    if (widget.offersOnly) return;

    // القسم اللي العميل اختاره من شاشة الأقسام بعد الدخول: نفتح محلاته على طول.
    final req = homeCategoryRequest.value;
    if (req != null) {
      homeCategoryRequest.value = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openDirectory(req);
      });
    }

    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid != null) {
      _unreadStream = FirebaseFirestore.instance
          .collection('notifications')
          .where('userId', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .limit(10) // العداد بيعرض 9+ أصلًا، فمفيش داعي نقرأ أكتر من كده.
          .snapshots().metered('home:unread-notifications');
    }

    _loadSavedAddress();
    _initNotifications();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) UpdateService.checkForUpdates(context);
    });
  }

  @override
  void dispose() {
    _courierStatusSubscription?.cancel();
    _bellCtrl.dispose();
    _player.dispose();
    super.dispose();
  }

  void _retry() {
    setState(() {
      _storesFuture = _loadStores();
      _offersFuture = null;
    });
  }

  /// فتح قائمة المحلات (لقسم معيّن أو الكل).
  void _openDirectory([String? category]) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => StoreDirectoryPage(initialCategory: category),
      ),
    );
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
            style: TextStyle(fontWeight: FontWeight.w800),
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

      final pos = await PerformanceMonitor.trace(
        'map_gps_location',
        () => Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
          ),
        ),
      );

      var text =
          '${pos.latitude.toStringAsFixed(5)}, ${pos.longitude.toStringAsFixed(5)}';
      try {
        final marks = await PerformanceMonitor.trace(
          'map_reverse_geocode',
          () => placemarkFromCoordinates(pos.latitude, pos.longitude),
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

  /// شرح واضح قبل طلب إذن الإشعارات، وقرار عرضه محفوظ محليًا لكل جهاز.
  Future<bool> _confirmNotificationsUse() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          title: const Text(
            'تفعيل الإشعارات',
            style: TextStyle(fontWeight: FontWeight.w800),
          ),
          content: const Text(
            'هنبعتلك إشعار لما حالة طلبك تتغيّر، وعشان توصلك العروض '
            'والخصومات الجديدة. تقدر توقفها في أي وقت من إعدادات الجهاز.',
            style: TextStyle(height: 1.6),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('مش دلوقتي'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('تفعيل'),
            ),
          ],
        ),
      ),
    );
    return ok ?? false;
  }

  /// الاشتراك في topic العروض العامة (all): للعملاء بس.
  /// الأدمن وأصحاب المحلات بنشيلهم منه لو كانوا مشتركين قبل كده.
  Future<void> _syncBroadcastTopic(String uid) async {
    try {
      // الاشتراك في topics للعرض فقط؛ صلاحيات الطلبات تظل محكومة بالسيرفر وFirestore.
      final known = RoleService.cachedFor(uid) ?? await RoleService.load();
      final roles = known.held;
      final isCourier = roles.contains(AppRole.courier);
      final isStaff = roles.contains(AppRole.admin) ||
          roles.contains(AppRole.storeOwner) ||
          roles.contains(AppRole.supervisor);
      final fm = FirebaseMessaging.instance;
      // تحديثات التطبيق تصل لكل الأدوار، بما فيها الإدارة وأصحاب المحلات.
      await fm.subscribeToTopic('app_updates');
      if (isStaff) {
        await fm.unsubscribeFromTopic('all');
      } else {
        await fm.subscribeToTopic('all');
      }
      await _syncCourierTopic(uid, isCourier);
    } catch (e) {
      debugPrint('Topic sync error: $e');
    }
  }

  /// إشعارات الطلبات الجديدة للمندوبين النشطين فقط.
  /// غياب active في السجلات القديمة يظل نشطًا، والقيمة false أو null توقف الاشتراك.
  Future<void> _syncCourierTopic(String uid, bool isCourier) async {
    await _courierStatusSubscription?.cancel();
    _courierStatusSubscription = null;
    final messaging = FirebaseMessaging.instance;
    if (!isCourier) {
      await messaging.unsubscribeFromTopic('couriers');
      return;
    }

    bool? lastSubscribedState;
    _courierStatusSubscription = FirebaseFirestore.instance
        .collection('couriers')
        .doc(uid)
        .snapshots()
        .listen(
      (snapshot) {
        final data = snapshot.data();
        final active = snapshot.exists &&
            data != null &&
            (!data.containsKey('active') || data['active'] == true);
        if (active == lastSubscribedState) return;
        lastSubscribedState = active;
        if (active) {
          unawaited(messaging.subscribeToTopic('couriers'));
        } else {
          unawaited(messaging.unsubscribeFromTopic('couriers'));
        }
      },
      onError: (Object error) {
        debugPrint('Courier notification status error: $error');
        lastSubscribedState = false;
        unawaited(messaging.unsubscribeFromTopic('couriers'));
      },
    );
  }

  Future<void> _initNotifications() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      if (await NotificationService.hasPermission()) {
        // الإذن قد يكون محفوظًا من جلسة سابقة؛ لازم نسجل FCM token ونربط listeners
        // في كل تشغيل، مش مجرد الاشتراك في topics.
        await NotificationService.init();
        await _syncBroadcastTopic(user.uid);
        return;
      }

      // حالة عرض الشرح محلية لكل جهاز؛ إذن أندرويد نفسه خاص بالجهاز وليس بالحساب.
      final prefs = await SharedPreferences.getInstance();
      final promptKey = 'notification_prompted_${user.uid}';
      if (prefs.getBool(promptKey) == true) return;

      // نعرض الشرح داخل التطبيق أولًا، ثم نطلب إذن أندرويد مرة واحدة.
      await Future<void>.delayed(const Duration(seconds: 3));
      if (!mounted) return;

      final accepted = await _confirmNotificationsUse();
      if (!mounted) return;
      if (!accepted) {
        await prefs.setBool(promptKey, true);
        return;
      }

      final granted =
          await NotificationService.requestPermissionAndRegister();
      await prefs.setBool(promptKey, true);

      if (!granted) {
        _toast('الإشعارات لسه مقفولة. تقدر تفعّلها من إعدادات التطبيق.');
        return;
      }
      await _syncBroadcastTopic(user.uid);
    } catch (e) {
      debugPrint('Notifications init error: $e');
    }
  }

  Future<void> _showNotificationSettingsHelp() async {
    final openSettings = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          title: const Text('الإشعارات غير مفعّلة'),
          content: const Text(
            'تقدر تشوف سجل إشعاراتك هنا، لكن علشان توصلك تنبيهات الطلبات فورًا '
            'افتح إعدادات التطبيق وفعّل السماح بالإشعارات.',
            style: TextStyle(height: 1.5),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('لاحقًا'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('فتح الإعدادات'),
            ),
          ],
        ),
      ),
    );
    if (openSettings == true) {
      await Geolocator.openAppSettings();
    }
  }

  Future<void> _openNotifications() async {
    // افتح الصفحة فورًا؛ أي مزامنة للتوكن/الـ topics تتم في الخلفية
    // علشان تعليق الشبكة أو FCM ما يوقفش الزر.
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => const NotificationsPage()));
    unawaited(_syncNotificationsInBackground());
  }

  Future<void> _syncNotificationsInBackground() async {
    try {
      final enabled = await NotificationService.hasPermission()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);
      if (!mounted) return;
      if (!enabled) {
        await _showNotificationSettingsHelp();
        return;
      }
      await NotificationService.init().timeout(const Duration(seconds: 15));
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid != null) await _syncBroadcastTopic(uid);
    } catch (e) {
      debugPrint('Notifications background sync error: $e');
    }
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
              width: 38,
              height: 38,
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

  /// الهيدر زي طلبات: لون واحد، "التوصيل إلى" فوق على جنب والسلة على الجنب التاني،
  /// وشريط البحث جوّه الهيدر نفسه، وحافة سفلية متموّجة.
  Widget _header() {
    final top = MediaQuery.paddingOf(context).top;
    return ClipPath(
      clipper: _WaveBottomClipper(),
      child: Container(
      color: Brand.green,
      padding: EdgeInsets.fromLTRB(16, top + 6, 16, 22),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: _pickLocation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'التوصيل إلى',
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontWeight: FontWeight.w600,
                          fontSize: 12,
                        ),
                      ),
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              _address.isEmpty ? 'اختر الموقع' : _address,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w800,
                                fontSize: 16,
                              ),
                            ),
                          ),
                          const Icon(
                            Icons.keyboard_arrow_down_rounded,
                            color: Colors.white,
                            size: 22,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              _bell(),
            ],
          ),
          const SizedBox(height: 8),
          _searchBar(),
        ],
      ),
      ),
    );
  }

  Widget _searchBar() {
    return Container(
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
              ),
      child: TextField(
        readOnly: true,
        onTap: _openDirectory,
        textInputAction: TextInputAction.search,
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        decoration: InputDecoration(
          hintText: 'ابحث عن مطعم أو محل...',
          hintStyle: TextStyle(
            color: Colors.grey.shade600,
            fontWeight: FontWeight.w600,
            fontSize: 14,
          ),
          prefixIcon: Icon(Icons.search_rounded, color: Colors.grey.shade600),
          filled: true,
          fillColor: Colors.transparent,
          contentPadding: const EdgeInsets.symmetric(vertical: 8),
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
    );
  }

  List<_StoreItem> _parse(List<CatalogDoc> docs) {
    final stores = <_StoreItem>[];
    for (final doc in docs) {
      try {
        final data = doc.data();
        final store = Store.fromMap(doc.id, data);
        if (store.active) stores.add(_StoreItem(store, data));
      } catch (e) {
        debugPrint('Error parsing store document ${doc.id}: $e');
      }
    }
    stores.sort((a, b) => a.store.order.compareTo(b.store.order));
    return stores;
  }

  Widget _offersPage() {
    final stores = _storesFuture;
    return Scaffold(
      appBar: AppBar(title: const Text('تصفح العروض')),
      body: FutureBuilder<List<(_StoreItem, Map<String, dynamic>)>>(
        future: _offersFuture ??= stores.then((docs) => _loadCatalogOffers(_parse(docs))),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Center(child: Text('تعذر تحميل العروض.'));
          }
          final offers = snapshot.data;
          if (offers == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (offers.isEmpty) {
            return const Center(child: Text('مفيش عروض متاحة دلوقتي.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: offers.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (_, i) => Align(
              alignment: AlignmentDirectional.centerStart,
              child: _offerCard(offers[i], offer: true),
            ),
          );
        },
      ),
    );
  }

  // ───────────────────────── البناء ─────────────────────────

  @override
  Widget build(BuildContext context) {
    if (widget.offersOnly) return _offersPage();
    return Container(
      color: Colors.white,
      child: FutureBuilder<List<CatalogDoc>>(
        future: _storesFuture,
        builder: (context, snapshot) {
          final loading = !snapshot.hasData && !snapshot.hasError;
          final hasError = snapshot.hasError && !snapshot.hasData;
          if (snapshot.hasError) {
            debugPrint('Firestore Error Details: ${snapshot.error}');
          }

          final all = snapshot.hasData ? _parse(snapshot.data!) : <_StoreItem>[];

          final scroll = CustomScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _header()),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const QuickOrderCreatePage(),
                      ),
                    ),
                    icon: const Icon(Icons.delivery_dining_outlined),
                    label: const Text('طلباتك على السريع'),
                  ),
                ),
              ),

              if (!loading && !hasError)
                SliverToBoxAdapter(child: _storeShortcuts(all)),

              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 18),
                  child: PromoBanners(),
                ),
              ),

              // Four real-photo cards in each row. Browse-stores and
              // browse-offers entry cards remain unchanged.
              SliverToBoxAdapter(
                child: HomeCategoryGrid(onSelected: (id) => _openDirectory(id)),
              ),

              if (!loading && !hasError)
                SliverToBoxAdapter(
                  child: _highlights(
                    all,
                    _offersFuture ??= _loadCatalogOffers(all),
                  ),
                ),

              if (loading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 18),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (hasError)
                SliverToBoxAdapter(
                  child: TextButton.icon(
                    onPressed: _retry,
                    icon: const Icon(Icons.refresh),
                    label: const Text('إعادة تحميل المحلات والعروض'),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 84)),
            ],
          );

          return Stack(
            children: [
              scroll,
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: MediaQuery.paddingOf(context).top,
                child: ColoredBox(color: Brand.green),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WaveBottomClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    const h = 12.0;
    final b = size.height - h;
    return Path()
      ..lineTo(0, b)
      ..quadraticBezierTo(size.width * 0.25, b + h * 1.6, size.width * 0.5, b + h * 0.5)
      ..quadraticBezierTo(size.width * 0.75, b - h * 0.6, size.width, b + h * 0.6)
      ..lineTo(size.width, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
