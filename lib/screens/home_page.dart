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
import '../services/navigation.dart';
import '../services/notification_service.dart';
import '../services/role_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../utils/format.dart';
import '../utils/img.dart';
import '../theme/brand.dart';
import '../widgets/category_tile.dart';
import '../widgets/promo_banners.dart';
import 'notifications_page.dart';
import 'store_page.dart';
import 'store_directory_page.dart';

const Map<String, String> kCategoryPhotos = {
  'مطاعم': 'https://images.unsplash.com/photo-1568901346375-23c9450c58cd?auto=format&fit=crop&w=700&q=70',
  'سوبرماركت': 'https://images.unsplash.com/photo-1542838132-92c53300491e?auto=format&fit=crop&w=700&q=70',
  'ورد': 'https://images.unsplash.com/photo-1490750967868-88aa4486c946?auto=format&fit=crop&w=700&q=70',
  // اسم القسم الفعلي في المحلات «ورد وهدايا»؛ المفتاح القديم «ورد» ما كانش بيطابقه فالصورة ما كانتش بتظهر.
  'ورد وهدايا': 'https://images.unsplash.com/photo-1490750967868-88aa4486c946?auto=format&fit=crop&w=700&q=70',
  // الصور التالية لم أتحقق من روابطها (لا يوجد اتصال بالإنترنت أثناء الكتابة). لو رابط ما فتحش
  // بيظهر الإيموجي الملوّن بدل الصورة، وتقدر تبدّله من Firestore (app_info/category_images) من غير نشر تحديث.
  'بقالة': 'https://images.unsplash.com/photo-1604719312566-8912e9227c6a?auto=format&fit=crop&w=700&q=70',
  'خضار وفاكهة': 'https://images.unsplash.com/photo-1540420773420-3366772f4999?auto=format&fit=crop&w=700&q=70',
  'لحوم ودواجن': 'https://images.unsplash.com/photo-1607623814075-e51df1bdc82f?auto=format&fit=crop&w=700&q=70',
  'مخبوزات وحلويات': 'https://images.unsplash.com/photo-1509440159596-0249088772ff?auto=format&fit=crop&w=700&q=70',
  'محمصات وعطارة': 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?auto=format&fit=crop&w=700&q=70',
  'كافيه ومشروبات': 'https://images.unsplash.com/photo-1495474472287-4d71bcdd2085?auto=format&fit=crop&w=700&q=70',
  'صيدليات': 'https://images.unsplash.com/photo-1576602976047-174e57a47881?auto=format&fit=crop&w=700&q=70',
};

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
  Future<QuerySnapshot<Map<String, dynamic>>> _storesFuture = _loadStores();
  Future<List<(_StoreItem, Map<String, dynamic>)>>? _offersFuture;

  static Future<QuerySnapshot<Map<String, dynamic>>> _loadStores() =>
      CatalogService.get(
        FirebaseFirestore.instance
            .collection('stores')
            .where('active', isEqualTo: true),
        'stores_active',
      );

  @override
  void initState() {
    super.initState();

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
                    onTap: () => _openDirectory(
                      info.category == 'الكل' ? null : info.category,
                    ),
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

  Future<List<(_StoreItem, Map<String, dynamic>)>> _loadCatalogOffers(
    List<_StoreItem> stores,
  ) async {
    final offers = <(_StoreItem, Map<String, dynamic>)>[];
    for (final store in stores) {
      var hasCatalog = false;
      try {
        Query<Map<String, dynamic>> query = FirebaseFirestore.instance
            .collection('stores')
            .doc(store.store.id)
            .collection('products')
            .limit(200);
        DocumentSnapshot<Map<String, dynamic>>? cursor;
        do {
          if (cursor != null) {
            query = FirebaseFirestore.instance
                .collection('stores')
                .doc(store.store.id)
                .collection('products')
                .limit(200)
                .startAfterDocument(cursor);
          }
          final page = await query.get();
          if (page.docs.isNotEmpty) hasCatalog = true;
          for (final doc in page.docs) {
            final item = doc.data();
            final name = (item['name'] ?? '').toString().trim();
            final price = (item['price'] as num?)?.toDouble() ?? 0;
            final old = (item['oldPrice'] as num?)?.toDouble() ?? 0;
            final text = (item['offerText'] ?? '').toString().trim();
            final end = item['offerEndsAt'];
            final expired = isOfferExpired(
              end is Timestamp ? end.toDate() : null,
              DateTime.now(),
            );
            if (name.isEmpty ||
                price <= 0 ||
                expired ||
                item['available'] == false ||
                item['isAvailable'] == false ||
                (!(old > price && old > 0) && text.isEmpty)) {
              continue;
            }
            offers.add((store, item));
          }
          cursor = page.docs.isEmpty ? null : page.docs.last;
          if (page.docs.length < 200) break;
        } while (cursor != null);
      } catch (error) {
        debugPrint('Home offers load failed for ${store.store.id}: $error');
      }
      // بيانات العروض المختصرة القديمة بديل عند عدم وجود كتالوج للمحل.
      if (!hasCatalog) {
        final raw = store.data['offerItems'];
        if (raw is List) {
          for (final value in raw) {
            if (value is! Map) continue;
            final item = Map<String, dynamic>.from(value);
            final end = item['offerEndsAt'];
            final price = (item['price'] as num?)?.toDouble() ?? 0;
            final old = (item['oldPrice'] as num?)?.toDouble() ?? 0;
            final text = (item['offerText'] ?? '').toString().trim();
            if (price <= 0 ||
                isOfferExpired(end is Timestamp ? end.toDate() : null, DateTime.now()) ||
                (!(old > price && old > 0) && text.isEmpty)) {
              continue;
            }
            offers.add((store, item));
          }
        }
      }
    }
    return offers;
  }

  Widget _highlights(
    List<_StoreItem> all,
    Future<List<(_StoreItem, Map<String, dynamic>)>> offersFuture,
  ) {
    final best = <(_StoreItem, Map<String, dynamic>)>[];
    for (final s in all) {
      if (s.data['active'] == false) continue;
      final raw = s.data['bestItems'];
      if (raw is! List) continue;
      for (final entry in raw) {
        if (entry is Map) {
          best.add((s, Map<String, dynamic>.from(entry)));
        }
      }
    }
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          FutureBuilder<List<(_StoreItem, Map<String, dynamic>)>>(
            future: offersFuture,
            builder: (context, snapshot) {
              final offers = snapshot.data ?? const <(_StoreItem, Map<String, dynamic>)>[];
              if (offers.isEmpty) return const SizedBox.shrink();
              return _hlRow('عروض وخصومات', offers, offer: true);
            },
          ),
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
    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.only(bottom: 14),
      color: offer ? kTileBeige.withValues(alpha: 0.55) : Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
            child: Row(
              children: [
                Icon(
                  offer ? Icons.local_offer_rounded : Icons.local_fire_department_rounded,
                  color: Brand.green,
                  size: 22,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    title,
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: Brand.ink,
                    ),
                  ),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 238,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: items.length > 12 ? 12 : items.length,
              separatorBuilder: (_, _) => const SizedBox(width: 12),
              itemBuilder: (_, i) => _offerCard(items[i], offer: offer),
            ),
          ),
        ],
      ),
    );
  }

  /// كارت عرض/صنف زي طلبات: صورة عريضة، شارة خصم، شعار المحل، الاسم والسعر.
  Widget _offerCard((_StoreItem, Map<String, dynamic>) entry, {bool offer = false}) {
    final (s, m) = entry;
    final price = (m['price'] as num?)?.toDouble() ?? 0;
    final old = (m['oldPrice'] as num?)?.toDouble() ?? 0;
    final img = (m['image'] ?? '').toString();
    final offerText = (m['offerText'] ?? '').toString().trim();
    final hasDiscount = old > price && old > 0;
    final badge = hasDiscount
        ? 'خصم ${((1 - price / old) * 100).round()}%'
        : offerText;
    final fallback = Container(
      decoration: BoxDecoration(gradient: Brand.softGradient),
      alignment: Alignment.center,
      child: Icon(s.store.icon, color: Colors.white70, size: 40),
    );
    return GestureDetector(
      onTap: () => _openStore(s.store),
      child: Container(
        width: 232,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: const [
            BoxShadow(color: Color(0x14000000), blurRadius: 10, offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              height: 130,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  img.isEmpty
                      ? fallback
                      : Image.network(
                          thumb(img, w: 500),
                          cacheWidth: 500,
                          fit: BoxFit.cover,
                          errorBuilder: (_, _, _) => fallback,
                        ),
                  if (badge.isNotEmpty)
                    PositionedDirectional(
                      top: 10,
                      start: 10,
                      child: Container(
                        constraints: const BoxConstraints(maxWidth: 150),
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFD6F24B),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text(
                          badge,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Color(0xFF1B1D22),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    bottom: 8,
                    end: 10,
                    child: Container(
                      width: 38,
                      height: 38,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: kLine),
                      ),
                      child: s.image.isEmpty
                          ? Icon(s.store.icon, size: 20, color: Brand.green)
                          : Image.network(
                              thumb(s.image, w: 120),
                              cacheWidth: 120,
                              fit: BoxFit.cover,
                              errorBuilder: (_, _, _) =>
                                  Icon(s.store.icon, size: 20, color: Brand.green),
                            ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (m['name'] ?? '').toString(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                      color: Brand.ink,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Icon(Icons.storefront_rounded, size: 14, color: kMuted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          s.store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: kMuted),
                        ),
                      ),
                      if (s.rating > 0) ...[
                        const Icon(Icons.star_rounded, color: Color(0xFFFFA000), size: 15),
                        Text(
                          s.rating.toStringAsFixed(1),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        formatPrice(price),
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: Brand.green,
                        ),
                      ),
                      if (offer && hasDiscount) ...[
                        const SizedBox(width: 8),
                        Text(
                          formatPrice(old),
                          style: TextStyle(
                            fontSize: 12,
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
  }

  // ───────────────────────── روابط المحلات المختصرة ─────────────────────────

  /// صف دوائر المحلات (شعار + اسم) زي طلبات: دخول سريع للمحل من الرئيسية.
  Widget _storeShortcuts(List<_StoreItem> all) {
    final shown = all.take(14).toList();
    if (shown.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'محلات مميزة',
                    style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      color: Brand.ink,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: _openDirectory,
                  child: const Text('عرض الكل'),
                ),
              ],
            ),
          ),
          SizedBox(
            height: 100,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: shown.length,
              separatorBuilder: (_, _) => const SizedBox(width: 14),
              itemBuilder: (_, i) {
                final item = shown[i];
                final fallback = Container(
                  color: Brand.green.withValues(alpha: 0.10),
                  alignment: Alignment.center,
                  child: Icon(item.store.icon, color: Brand.green, size: 28),
                );
                return GestureDetector(
                  onTap: () => _openStore(item.store),
                  child: SizedBox(
                    width: 72,
                    child: Column(
                      children: [
                        Container(
                          width: 66,
                          height: 66,
                          clipBehavior: Clip.antiAlias,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: kLine, width: 1.5),
                          ),
                          child: item.image.isEmpty
                              ? fallback
                              : Image.network(
                                  thumb(item.image, w: 200),
                                  cacheWidth: 200,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => fallback,
                                ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          item.store.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w800,
                            color: Brand.ink,
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
      ),
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

          final scroll = CustomScrollView(
            physics: const BouncingScrollPhysics(),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            slivers: [
              SliverToBoxAdapter(child: _header()),

              // الصفحة الرئيسية: بنرات، روابط المحلات، الأقسام، العروض، الأكثر مبيعًا.
              const SliverToBoxAdapter(
                child: Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: PromoBanners(),
                ),
              ),

              if (!loading && !hasError)
                SliverToBoxAdapter(child: _storeShortcuts(all)),

              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          'تصفّح الأقسام',
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: Brand.ink),
                        ),
                      ),
                      TextButton(
                        onPressed: _openDirectory,
                        child: const Text('كل المحلات'),
                      ),
                    ],
                  ),
                ),
              ),

              SliverToBoxAdapter(
                child: _categoriesRow(parsed.categoryImages),
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
                    label: const Text('إعادة تحميل العروض والأقسام'),
                  ),
                ),

              const SliverToBoxAdapter(child: SizedBox(height: 84)),
            ],
          );

          return scroll;
        },
      ),
    );
  }
}

/// مربع قسم بصورة حقيقية على خلفية بيج، زي تطبيقات التوصيل الكبيرة.
class _CategoryTile extends StatelessWidget {
  final String label;
  final String imageUrl;
  final bool isAll;
  final VoidCallback onTap;
  const _CategoryTile({
    required this.label,
    required this.imageUrl,
    required this.isAll,
    required this.onTap,
  });

  /// أيقونة ملوّنة لكل قسم لما مفيش صورة (بتظهر مظبوطة على الموبايل والويب).
  static String _emojiFor(String label) {
    if (label == 'الكل') return '🛍️';
    const map = <String, String>{
      'مطاعم': '🍔',
      'سوبرماركت': '🛒',
      'بقالة': '🧺',
      'خضار وفاكهة': '🥬',
      'لحوم ودواجن': '🥩',
      'مخبوزات وحلويات': '🥐',
      'محمصات وعطارة': '🌰',
      'كافيه ومشروبات': '☕',
      'ورد وهدايا': '💐',
      'أخرى': '📦',
    };
    final exact = map[label];
    if (exact != null) return exact;
    // احتياطي لو اسم القسم اتغيّر شوية.
    if (label.contains('مطعم') || label.contains('وجبات')) return '🍔';
    if (label.contains('خضار') || label.contains('فاكه')) return '🥬';
    if (label.contains('لحوم') || label.contains('دواجن')) return '🥩';
    if (label.contains('مخبوز') || label.contains('حلوي')) return '🥐';
    if (label.contains('كافيه') || label.contains('مشروب')) return '☕';
    if (label.contains('ورد') || label.contains('هدا')) return '💐';
    if (label.contains('عطار') || label.contains('محمص')) return '🌰';
    if (label.contains('صيدل')) return '💊';
    if (label.contains('ماركت') || label.contains('بقال')) return '🛒';
    return '📦';
  }

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
            color: Colors.transparent,
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
                    ? _emojiBox()
                    : Image.network(
                        thumb(imageUrl, w: 200),
                        cacheWidth: 200,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => _emojiBox(),
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
                color: Brand.ink,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emojiBox() {
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(gradient: Brand.softGradient),
      child: Text(
        _emojiFor(label),
        style: const TextStyle(fontSize: 32, height: 1.1),
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
