import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../services/notification_service.dart';
import '../services/resume_session.dart';
import '../services/saved_address.dart';
import '../services/location_picker.dart';
import '../theme/app_tokens.dart';
import '../services/cart_book.dart';
import '../services/order_gateway.dart';
import '../widgets/home_top_ads.dart' show loadTourPosters;
import '../widgets/curved_nav_bar.dart';
import '../widgets/invite_code_field.dart';
import '../widgets/service_entry_card.dart';
import 'account_page.dart';
import 'home_page.dart';
import 'main_shell.dart';
import 'notifications_page.dart';
import 'onboarding_page.dart';
import 'quick_order_create_page.dart';
import 'errand_create_page.dart';
import 'store_directory_page.dart';
import 'store_link_page.dart';

/// صور الواجهة مأخوذة من التصميم المرجعي المعتمد لصفحة ما بعد الدخول.
const kEntryQuickAsset = 'assets/images/entry_quick.jpg';
const kEntryOffersAsset = 'assets/images/entry_offers.jpg';
const kEntryStoresAsset = 'assets/images/entry_stores.jpg';
const kEntryErrandAsset = 'assets/images/entry_errand.jpg';
const kWasallyLogoLightAsset = 'assets/images/wasally_logo_light.png';

/// واجهة اختيار الخدمات بعد تسجيل الدخول (لكل الأدوار).
/// الأدوار التانية بتحتفظ بلوحتها وصلاحياتها خلف زر «لوحتي».
class CustomerEntry extends StatefulWidget {
  const CustomerEntry({
    super.key,
    this.dashboard,
    this.dashboardLabel,
    this.showInviteCode,
  });

  final Widget? dashboard;
  final String? dashboardLabel;

  /// خانة كود الدعوة بدل البحث (الافتراضي: لما حملة الدعوات مفعلة).
  final bool? showInviteCode;

  @override
  State<CustomerEntry> createState() => _CustomerEntryState();
}

class _CustomerEntryState extends State<CustomerEntry> {
  bool _entered = false;

  /// الإعلانات تظهر الأول: صفحة ما بعد الدخول مستخبية لحد ما نعرف هل فيه جولة
  /// ولحد ما الجولة تتقفل (بدل ما الصفحة تبان لحظة وبعدين الإعلان يطلع فوقها).
  bool _waitingForTour = OnboardingStore.hasAccount && !ResumeSession.resumedRecently;

  bool get _isCustomer => widget.dashboard == null;

  @override
  void initState() {
    super.initState();
    customerShellAvailable.value = _isCustomer;
    enterShellRequest.addListener(_onEnterShellRequest);
    servicesPageRequest.addListener(_onServicesRequest);
    shellTab.addListener(_saveLocation);
    SavedAddress.load();
    _restoreAfterResume();
    unawaited(_startWelcomeFlows());
  }

  static String get _uid {
    try {
      return FirebaseAuth.instance.currentUser?.uid ?? '';
    } catch (_) {
      return ''; // widget tests من غير Firebase
    }
  }

  /// #326: أندرويد قفل التطبيق في الخلفية والعميل رجع خلال دقايق:
  /// نرجّعه لنفس التبويب/المحل بدل صفحة الخدمات (من غير قراءات Firestore زيادة).
  void _restoreAfterResume() {
    if (!ResumeSession.resumedRecently) return;
    final uid = _uid;
    final location = ResumeSession.takeLocation(uid);
    if (location == null) return;
    if (location == 'dashboard' && !_isCustomer) {
      _entered = true;
    } else if (!_isCustomer) {
      return;
    } else if (location.startsWith('shell:')) {
      final tab = int.tryParse(location.substring(6)) ?? 0;
      shellTab.value = tab.clamp(0, 3);
      _entered = true;
    } else if (location.startsWith('store:')) {
      final id = location.substring(6);
      if (id.isEmpty) return;
      shellTab.value = 0;
      _entered = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = rootNavigatorKey.currentState;
        if (!mounted || nav == null) return;
        nav.push(MaterialPageRoute<void>(builder: (_) => StoreLinkPage(storeId: id)));
      });
    }
    ResumeSession.setLocation(uid, location);
  }

  /// الشاشة الرئيسية الحالية للعميل (تبويب الشريط) عشان الرجوع بعد قفل التطبيق.
  void _saveLocation() {
    if (!_isCustomer || !_entered) return;
    final current = ResumeSession.current;
    if (current != null && current.startsWith('store:')) return; // جوه محل
    ResumeSession.setLocation(_uid, 'shell:${shellTab.value}');
  }

  /// Ask for push after onboarding even if the user never opens Home.
  Future<void> _startWelcomeFlows() async {
    try {
      await _maybeShowTour();
    } catch (e) {
      debugPrint('Welcome tour failed: $e');
    } finally {
      if (mounted && _waitingForTour) setState(() => _waitingForTour = false);
    }
    if (!mounted) return;
    await NotificationService.ensurePermissionWithExplanation(context);
  }

  /// الجولة الإعلانية لكل الحسابات، لحد مرتين في اليوم (محليًا).
  Future<void> _maybeShowTour() async {
    // رجوع بعد ما أندرويد قفل التطبيق في الخلفية: مش فتح جديد، فمفيش إعلانات.
    if (ResumeSession.resumedRecently) return;
    if (!await OnboardingStore.shouldShow() || !mounted) return;
    // صور الإدارة لو موجودة، وإلا الجولة المدمجة.
    final posters = await loadTourPosters();
    if (!mounted) return;
    // من غير أنيميشن دخول: الإعلان يبان مكان شاشة البداية على طول.
    await Navigator.of(context).push(PageRouteBuilder<void>(
      fullscreenDialog: true,
      transitionDuration: Duration.zero,
      reverseTransitionDuration: const Duration(milliseconds: 220),
      pageBuilder: (_, _, _) => OnboardingPage(posters: posters),
      transitionsBuilder: (_, animation, _, child) =>
          FadeTransition(opacity: animation, child: child),
    ));
  }

  @override
  void dispose() {
    enterShellRequest.removeListener(_onEnterShellRequest);
    servicesPageRequest.removeListener(_onServicesRequest);
    shellTab.removeListener(_saveLocation);
    super.dispose();
  }

  /// زرار «الخدمات» في الرئيسية: نرجع لكروت الخدمات.
  void _onServicesRequest() {
    if (!mounted || !_entered) return;
    setState(() => _entered = false);
    shellTab.value = 0;
    ResumeSession.setLocation(_uid, null);
  }

  /// صفحة داخلية (مثل صفحة التسوق) طلبت تبويبًا من الشريط السفلي.
  void _onEnterShellRequest() {
    if (!mounted || !_isCustomer || _entered) return;
    setState(() => _entered = true);
    _saveLocation();
  }

  void _enter([Widget? destination, int tab = 0]) {
    if (_entered) return;
    if (destination != null) {
      // Leaving a service must return to the entry cards, not skip them.
      Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => destination),
      );
      return;
    }
    shellTab.value = tab;
    setState(() => _entered = true);
    if (_isCustomer) {
      _saveLocation();
    } else {
      ResumeSession.setLocation(_uid, 'dashboard');
    }
  }

  void _openNotifications() =>
      pushOnce<void>(context, 'notifications', (_) => const NotificationsPage());

  Widget get _dashboard => widget.dashboard ?? const MainShell();

  // ───────────────────────── الهيدر ─────────────────────────

  Widget _headerIcon(IconData icon, String label, VoidCallback onTap) {
    return IconButton(
      key: ValueKey<String>('entry-$label'),
      tooltip: label,
      onPressed: onTap,
      style: IconButton.styleFrom(
        minimumSize: const Size(kMinTapTarget, kMinTapTarget),
        foregroundColor: Colors.white,
      ),
      icon: Icon(icon, size: 28, color: Colors.white),
    );
  }

  /// الهيدر ثابت برا القائمة: أزراره بتستجيب من أول ضغطة حتى أثناء التمرير.
  Widget _header(BuildContext context) {
    final top = MediaQuery.paddingOf(context).top;
    return ClipPath(
      key: const Key('entry-header-wave'),
      clipper: const _EntryHeaderWaveClipper(),
      child: Container(
        color: AppColors.purpleDeep,
        padding: EdgeInsets.fromLTRB(
          AppSpacing.md, top, AppSpacing.md, AppSpacing.sm + 28,
        ),
        child: Column(
          children: [
          Row(
            children: [
              Expanded(child: _location()),
              _headerIcon(Icons.notifications_none_rounded, 'الإشعارات', _openNotifications),
              _headerIcon(Icons.person_outline_rounded, 'حسابي',
                  () => _enter(const _StandaloneAccount())),
            ],
          ),
          Semantics(
            label: 'وصّلي',
            image: true,
            child: Image.asset(
              kWasallyLogoLightAsset,
              height: 36,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          if (widget.showInviteCode ?? OrderGateway.referralCampaignEnabled)
            const InviteCodeField(key: Key('entry-invite-code'))
          else
            _searchBar(),
          ],
        ),
      ),
    );
  }

  Widget _location() {
    return ValueListenableBuilder<String>(
      valueListenable: SavedAddress.value,
      builder: (context, address, _) => InkWell(
        key: const Key('entry-location'),
        borderRadius: BorderRadius.circular(AppRadius.md),
        // يفتح اختيار عنوان التوصيل مباشرة (موقعي الحالي أو كتابة العنوان).
        onTap: () => DeliveryLocationPicker.open(context),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: kMinTapTarget),
          child: Row(
            children: [
              const Icon(Icons.location_on_outlined, color: Colors.white, size: 26),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text.rich(
                  TextSpan(children: [
                    TextSpan(
                      text: 'التوصيل إلى: ',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.82),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    TextSpan(
                      text: address.isEmpty ? 'حدد عنوانك' : address,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ]),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: AppTypography.bodySmall - 1),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _searchBar() {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(AppRadius.pill),
      elevation: 2,
      shadowColor: Colors.black26,
      child: InkWell(
        key: const Key('entry-search'),
        borderRadius: BorderRadius.circular(AppRadius.pill),
        onTap: () => _enter(const StoreDirectoryPage()),
        child: SizedBox(
          height: 46,
          child: Row(
            children: [
              const SizedBox(width: AppSpacing.xl),
              const Expanded(
                child: Text(
                  'ابحث عن محل أو ماركت...',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: AppColors.muted,
                    fontSize: AppTypography.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(Icons.search_rounded, color: AppColors.muted.withValues(alpha: 0.9), size: 26),
              const SizedBox(width: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── كروت الخدمات ─────────────────────────

  Widget _serviceCard({
    required String title,
    required String subtitle,
    required String action,
    String? asset,
    IconData icon = Icons.delivery_dining_rounded,
    required VoidCallback onTap,
    required double height,
  }) =>
      ServiceEntryCard(
        title: title,
        subtitle: subtitle,
        action: action,
        asset: asset,
        icon: icon,
        onTap: onTap,
        height: height,
      );

  /// أقل ارتفاع للكارت يكفي العنوان والوصف والزر (حسب حجم الخط).
  double _minCardHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return scale.scale(17) * 1.2 +
        scale.scale(AppTypography.caption - 1) * 1.25 +
        34 +
        AppSpacing.sm * 2 +
        AppSpacing.xs * 2;
  }

  List<Widget> _cards(double height) => [
        _serviceCard(
          title: 'خدمة وصّلي ع السريع',
          subtitle: 'اطلب احتياجاتك من أي مكان',
          action: 'اطلب الآن',
          asset: kEntryQuickAsset,
          height: height,
          onTap: () => _enter(const QuickOrderCreatePage()),
        ),
        _serviceCard(
          title: 'مشاويرك علينا',
          subtitle: 'مندوب لأي مشوار داخل مدينتك',
          action: 'اطلب مشوار',
          asset: kEntryErrandAsset,
          height: height,
          onTap: () => _enter(const ErrandCreatePage()),
        ),
        _serviceCard(
          title: 'تصفح العروض',
          subtitle: 'أقوى الخصومات والعروض الحصرية',
          action: 'شاهد العروض',
          asset: kEntryOffersAsset,
          height: height,
          onTap: () => _enter(const HomePage(offersOnly: true)),
        ),
        _serviceCard(
          title: 'تصفح المحلات',
          subtitle: 'اكتشف جميع المحلات والأصناف',
          action: 'استعرض المحلات',
          asset: kEntryStoresAsset,
          height: height,
          onTap: () => _enter(const StoreDirectoryPage()),
        ),
      ];

  /// الخدمات الأربعة بنفس شكل الكارت، وبتملأ المساحة تحت الهيدر المموج في
  /// شاشة واحدة على الموبايلات العادية. الشاشات الصغيرة جدًا أو الخط المكبّر
  /// بتسمح بالتمرير بدل ضغط النص أو إخفاء الأزرار.
  Widget _body(BuildContext context) {
    const gap = AppSpacing.md;
    final minCard = _minCardHeight(context);
    return LayoutBuilder(builder: (context, box) {
      const count = 4; // عدد كروت _cards
      final available = box.maxHeight - gap * (count + 1);
      var card = available / count;
      final maxCard = (box.maxWidth * 0.40).clamp(110.0, 170.0).toDouble();
      if (card > maxCard) card = maxCard;
      final fits = card >= minCard;
      if (!fits) card = minCard;
      return ListView(
        key: const Key('entry-list'),
        physics: fits ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.only(bottom: gap),
        children: [
          for (final service in _cards(card))
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, gap, AppSpacing.md, 0),
              child: service,
            ),
        ],
      );
    });
  }

  void _openShell(int tab) {
    shellTab.value = tab;
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const MainShell()));
  }

  /// نفس شكل شريط العميل (السلة الكبيرة في النص)، و«لوحتي» مكان «طلباتي».
  Widget _staffNav() => ListenableBuilder(
        listenable: carts,
        builder: (context, _) => CurvedNavBar(
          index: 0,
          centerIndex: 2,
          onTap: (i) {
            switch (i) {
              case 0:
                _openShell(0);
              case 1:
                _enter();
              case 2:
                _openShell(1);
              case 3:
                _enter(const StoreDirectoryPage());
              default:
                _enter(const _StandaloneAccount());
            }
          },
          items: [
            const AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'الرئيسية'),
            const AppNavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'لوحتي'),
            AppNavItem(
              icon: Icons.shopping_cart_outlined,
              selectedIcon: Icons.shopping_cart_rounded,
              label: 'السلة',
              badge: carts.totalItems,
            ),
            const AppNavItem(icon: Icons.storefront_outlined, selectedIcon: Icons.storefront_rounded, label: 'المحلات'),
            const AppNavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'حسابي'),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (_entered) return _dashboard;
    if (_waitingForTour) {
      // شاشة البداية بلون التطبيق لحد ما الإعلان يظهر (أقل من ثانية غالبًا).
      return Scaffold(
        key: const Key('entry-waiting-for-tour'),
        backgroundColor: AppColors.purpleDeep,
        body: Center(
          child: Image.asset(kWasallyLogoLightAsset, width: 150, excludeFromSemantics: true),
        ),
      );
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _header(context),
          Expanded(child: _body(context)),
        ],
      ),
      bottomNavigationBar: _isCustomer
          // Approved order: السلة، طلباتي، الرئيسية، حسابي.
          ? CustomerBottomNav(currentTab: 0, onTab: (tab) => _enter(null, tab))
          // لوحة الدور من زر «لوحتي» في الشريط.
          : _staffNav(),
    );
  }
}

/// صفحة «حسابي» لما تتفتح من صفحة الترحيب: لازم Scaffold (كانت بتظهر
/// شاشة خطأ «No Material widget found» لأنها مصممة كتبويب داخلي).
class _StandaloneAccount extends StatelessWidget {
  const _StandaloneAccount();

  @override
  Widget build(BuildContext context) => const Scaffold(body: AccountPage());
}

/// الحافة السفلية المموجة للهيدر، من غير طبقة تغطي الكروت أو الأزرار.
class _EntryHeaderWaveClipper extends CustomClipper<Path> {
  const _EntryHeaderWaveClipper();

  @override
  Path getClip(Size size) {
    final w = size.width;
    final h = size.height;
    return Path()
      ..moveTo(0, 0)
      ..lineTo(0, h - 24)
      ..cubicTo(w * 0.28, h + 5, w * 0.72, h - 40, w, h - 18)
      ..lineTo(w, 0)
      ..close();
  }

  @override
  bool shouldReclip(covariant _EntryHeaderWaveClipper oldClipper) => false;
}
