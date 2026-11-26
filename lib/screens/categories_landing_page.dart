import 'dart:async';

import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../services/notification_service.dart';
import '../services/saved_address.dart';
import '../services/location_picker.dart';
import '../theme/app_tokens.dart';
import '../services/cart_book.dart';
import '../services/order_gateway.dart';
import '../widgets/home_top_ads.dart' show loadTourPosters;
import '../widgets/curved_nav_bar.dart';
import '../widgets/invite_code_field.dart';
import 'account_page.dart';
import 'home_page.dart';
import 'main_shell.dart';
import 'notifications_page.dart';
import 'onboarding_page.dart';
import 'quick_order_create_page.dart';
import 'store_directory_page.dart';

/// صور الواجهة مأخوذة من التصميم المرجعي المعتمد لصفحة ما بعد الدخول.
const kEntryQuickAsset = 'assets/images/entry_quick.jpg';
const kEntryOffersAsset = 'assets/images/entry_offers.jpg';
const kEntryStoresAsset = 'assets/images/entry_stores.jpg';
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

  bool get _isCustomer => widget.dashboard == null;

  @override
  void initState() {
    super.initState();
    customerShellAvailable.value = _isCustomer;
    enterShellRequest.addListener(_onEnterShellRequest);
    SavedAddress.load();
    unawaited(_startWelcomeFlows());
  }

  /// Ask for push after onboarding even if the user never opens Home.
  Future<void> _startWelcomeFlows() async {
    try {
      await _maybeShowTour();
    } catch (e) {
      debugPrint('Welcome tour failed: $e');
    }
    if (!mounted) return;
    await NotificationService.ensurePermissionWithExplanation(context);
  }

  /// الجولة الإعلانية لكل الحسابات، لحد مرتين في اليوم (محليًا).
  Future<void> _maybeShowTour() async {
    if (!await OnboardingStore.shouldShow() || !mounted) return;
    // صور الإدارة لو موجودة، وإلا الجولة المدمجة.
    final posters = await loadTourPosters();
    if (!mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => OnboardingPage(posters: posters),
    ));
  }

  @override
  void dispose() {
    enterShellRequest.removeListener(_onEnterShellRequest);
    super.dispose();
  }

  /// صفحة داخلية (مثل صفحة التسوق) طلبت تبويبًا من الشريط السفلي.
  void _onEnterShellRequest() {
    if (!mounted || !_isCustomer || _entered) return;
    setState(() => _entered = true);
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

  /// كارت زي التصميم المرجعي: الصورة الواقعية على اليسار وبتتلاشى في
  /// الأبيض تحت النص، والأيقونة والعنوان والوصف والزر على اليمين.
  Widget _serviceCard({
    required String title,
    required String subtitle,
    required String action,
    required String asset,
    required VoidCallback onTap,
    required double height,
  }) {
    return SizedBox(
      height: height,
      child: Material(
        elevation: 3,
        shadowColor: AppColors.ink.withValues(alpha: 0.12),
        color: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: const BorderSide(color: AppColors.line),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: ValueKey<String>('entry-card-$title'),
          onTap: onTap,
          splashColor: AppColors.purple.withValues(alpha: 0.08),
          highlightColor: AppColors.purple.withValues(alpha: 0.04),
          child: LayoutBuilder(builder: (context, box) {
            final artWidth = box.maxWidth * 0.74;
            return Stack(
              children: [
                // الصورة نفسها بتذوب في الأبيض تدريجيًا (شفافية مش طبقة بيضا)،
                // فمفيش حد/هامش ظاهر بين الصورة والكارت.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: artWidth,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (rect) => const LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      stops: [0.0, 0.42, 0.68, 0.92],
                      colors: [Colors.black, Colors.black, Color(0x66000000), Color(0x00000000)],
                    ).createShader(rect),
                    child: Image.asset(
                      asset,
                      key: ValueKey<String>('entry-art-$title'),
                      fit: BoxFit.cover,
                      alignment: Alignment.centerLeft,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                PositionedDirectional(
                  start: 0,
                  top: 0,
                  bottom: 0,
                  width: box.maxWidth * 0.56,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md, AppSpacing.sm, AppSpacing.xs, AppSpacing.sm),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            title,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.ink,
                              fontSize: 17,
                              height: 1.2,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.caption - 1,
                              height: 1.25,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Container(
                          height: 34,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.orangeLight, AppColors.orange, AppColors.orangeDeep],
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.orange.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          // يفضل في سطر واحد كامل من غير «...» حتى في الشاشات الضيقة.
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text(
                              action,
                              maxLines: 1,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: AppTypography.label - 1,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          }),
        ),
      ),
    );
  }

  /// أقل ارتفاع للكارت يكفي العنوان والوصف والزر (حسب حجم الخط).
  double _minCardHeight(BuildContext context) {
    final scale = MediaQuery.textScalerOf(context);
    return scale.scale(17) * 1.2 +
        scale.scale(AppTypography.caption - 1) * 1.25 +
        34 +
        AppSpacing.sm * 2 +
        AppSpacing.md * 2;
  }

  List<Widget> _cards(double height) => [
        _serviceCard(
          title: 'خدمة وصّلي ع السريع',
          subtitle: 'طلباتك اليومية وتوصيلها بسرعة',
          action: 'اطلب الآن',
          asset: kEntryQuickAsset,
          height: height,
          onTap: () => _enter(const QuickOrderCreatePage()),
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

  /// الكروت الثلاثة تملأ المساحة المتاحة أسفل الهيدر المموج.
  /// الشاشات الصغيرة تسمح بالتمرير بدل ضغط النص أو إخفاء الأزرار.
  Widget _body(BuildContext context) {
    const gap = AppSpacing.md;
    final minCard = _minCardHeight(context);
    return LayoutBuilder(builder: (context, box) {
      final available = box.maxHeight - gap * 4;
      var card = available / 3;
      final maxCard = (box.maxWidth * 0.40).clamp(140.0, 180.0).toDouble();
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
