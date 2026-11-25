import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../services/saved_address.dart';
import '../services/location_picker.dart';
import '../theme/app_tokens.dart';
import '../services/cart_book.dart';
import '../services/order_gateway.dart';
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
const kEntryBannerAsset = 'assets/images/entry_banner.jpg';
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
    if (_isCustomer) _maybeShowTour();
  }

  /// الجولة التعريفية بعد أول دخول للعميل (مرة واحدة لكل حساب، محليًا).
  Future<void> _maybeShowTour() async {
    if (!await OnboardingStore.shouldShow() || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => const OnboardingPage(),
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
    return Container(
      color: AppColors.purpleDeep,
      padding: EdgeInsets.fromLTRB(AppSpacing.md, top, AppSpacing.md, AppSpacing.sm),
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
                  style: const TextStyle(fontSize: AppTypography.bodySmall),
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

  // ───────────────────────── البانر ─────────────────────────

  /// البانر صورة واحدة: صورة الساندوتش والمشروب بتذوب في الخلفية
  /// البنفسجي والكلام «وصّلي... لحد عندي» فوقها، زي التصميم المرجعي.
  Widget _banner(double height) {
    return SizedBox(
      height: height,
      child: Material(
        key: const Key('entry-banner'),
        elevation: 5,
        shadowColor: AppColors.purpleDeep.withValues(alpha: 0.35),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          side: BorderSide(color: AppColors.orange.withValues(alpha: 0.75), width: 1.2),
        ),
        clipBehavior: Clip.antiAlias,
        child: Ink(
          decoration: const BoxDecoration(
            // نفس ألوان حافة الصورة علشان مايبانش فاصل.
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [Color(0xFF27105E), Color(0xFF1D0B52)],
            ),
          ),
          child: InkWell(
            onTap: () => _enter(const StoreDirectoryPage()),
            child: LayoutBuilder(builder: (context, box) {
              return Stack(
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    bottom: 0,
                    width: box.maxWidth * 0.74,
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (rect) => const LinearGradient(
                        begin: Alignment.centerLeft,
                        end: Alignment.centerRight,
                        stops: [0.0, 0.72, 1.0],
                        colors: [Colors.white, Colors.white, Color(0x00FFFFFF)],
                      ).createShader(rect),
                      child: Image.asset(
                        kEntryBannerAsset,
                        key: const Key('entry-banner-art'),
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
                    width: box.maxWidth * 0.44,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          AppSpacing.lg, AppSpacing.md, AppSpacing.xs, AppSpacing.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Flexible(
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: AlignmentDirectional.centerStart,
                              child: Text(
                                'وصّلي...\nلحد عندي',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  height: 1.2,
                                  fontWeight: FontWeight.w900,
                                  shadows: [Shadow(color: Color(0x66000000), blurRadius: 8)],
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
                            decoration: BoxDecoration(
                              color: const Color(0xCC5A3524),
                              borderRadius: BorderRadius.circular(AppRadius.pill),
                            ),
                            child: const Text(
                              'اطلب الآن',
                              maxLines: 1,
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: AppTypography.label,
                                fontWeight: FontWeight.w800,
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
    required IconData icon,
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
            final artWidth = box.maxWidth * 0.52;
            return Stack(
              children: [
                // الصورة + تلاشي ناعم للأبيض ناحية النص.
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: artWidth,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      Image.asset(
                        asset,
                        key: ValueKey<String>('entry-art-$title'),
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                        excludeFromSemantics: true,
                      ),
                      const DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                            stops: [0.0, 0.62, 1.0],
                            colors: [Color(0x00FFFFFF), Color(0x00FFFFFF), Colors.white],
                          ),
                        ),
                      ),
                    ],
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
                        Row(
                          children: [
                            Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [AppColors.orangeLight, AppColors.orangeDeep],
                                ),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(icon, color: Colors.white, size: 21),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: AlignmentDirectional.centerStart,
                                child: Text(
                                  title,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: AppColors.ink,
                                    fontSize: 18,
                                    height: 1.2,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        FittedBox(
                          fit: BoxFit.scaleDown,
                          alignment: AlignmentDirectional.centerStart,
                          child: Text(
                            subtitle,
                            maxLines: 1,
                            style: const TextStyle(
                              color: AppColors.muted,
                              fontSize: AppTypography.caption,
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
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  action,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: AppTypography.label,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 2),
                                const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 18),
                              ],
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
    return scale.scale(18) * 1.2 +
        scale.scale(AppTypography.caption) * 1.25 +
        34 +
        AppSpacing.sm * 2 +
        AppSpacing.md * 2;
  }

  List<Widget> _cards(double height) => [
        _serviceCard(
          title: 'خدمة وصّلي ع السريع',
          subtitle: 'طلباتك اليومية وتوصيلها بسرعة',
          action: 'اطلب الآن',
          icon: Icons.bolt_rounded,
          asset: kEntryQuickAsset,
          height: height,
          onTap: () => _enter(const QuickOrderCreatePage()),
        ),
        _serviceCard(
          title: 'تصفح العروض',
          subtitle: 'أقوى الخصومات والعروض الحصرية',
          action: 'شاهد العروض',
          icon: Icons.percent_rounded,
          asset: kEntryOffersAsset,
          height: height,
          onTap: () => _enter(const HomePage(offersOnly: true)),
        ),
        _serviceCard(
          title: 'تصفح المحلات',
          subtitle: 'اكتشف جميع المحلات والأصناف',
          action: 'استعرض المحلات',
          icon: Icons.storefront_rounded,
          asset: kEntryStoresAsset,
          height: height,
          onTap: () => _enter(const StoreDirectoryPage()),
        ),
      ];

  /// البانر والكروت الثلاثة بيتقسموا المساحة المتاحة بالظبط زي التصميم
  /// المرجعي، فالصفحة كلها ظاهرة من غير تمرير. على الشاشات الصغيرة جدًا
  /// بس بيتحول لقائمة قابلة للتمرير بدل ما المحتوى يتضغط.
  Widget _body(BuildContext context) {
    const gap = AppSpacing.md;
    final minCard = _minCardHeight(context);
    return LayoutBuilder(builder: (context, box) {
      final available = box.maxHeight - gap * 4;
      // نسبة البانر للكارت في التصميم المرجعي ≈ 1.3.
      var card = available / 4.3;
      var banner = card * 1.3;
      final fits = card >= minCard;
      if (!fits) {
        card = minCard;
        banner = (box.maxWidth - AppSpacing.md * 2) / 2.4;
      }
      // لا نكبر الكروت أكتر من اللازم على الشاشات الطويلة.
      final maxCard = box.maxWidth * 0.36;
      if (card > maxCard) {
        card = maxCard;
        banner = maxCard * 1.3;
      }
      final children = <Widget>[
        Stack(children: [
          // امتداد لون الهيدر خلف نصف البانر العلوي زي التصميم المرجعي.
          Container(height: banner / 2 + gap, color: AppColors.purpleDeep),
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, gap, AppSpacing.md, 0),
            child: _banner(banner),
          ),
        ]),
        for (final c in _cards(card))
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, gap, AppSpacing.md, 0),
            child: c,
          ),
      ];
      return ListView(
        key: const Key('entry-list'),
        physics: fits ? const NeverScrollableScrollPhysics() : null,
        padding: const EdgeInsets.only(bottom: gap),
        children: children,
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
                _openNotifications();
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
            const AppNavItem(icon: Icons.notifications_none_rounded, selectedIcon: Icons.notifications_rounded, label: 'الإشعارات'),
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
