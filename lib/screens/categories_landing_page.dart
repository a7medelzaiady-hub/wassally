import 'package:flutter/material.dart';

import '../services/navigation.dart';
import '../services/saved_address.dart';
import '../theme/app_tokens.dart';
import '../widgets/curved_nav_bar.dart';
import 'account_page.dart';
import 'home_page.dart';
import 'main_shell.dart';
import 'notifications_page.dart';
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
  });

  final Widget? dashboard;
  final String? dashboardLabel;

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
      padding: EdgeInsets.fromLTRB(AppSpacing.md, top + 2, AppSpacing.md, AppSpacing.md),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(child: _location()),
              _headerIcon(Icons.notifications_none_rounded, 'الإشعارات', _openNotifications),
              _headerIcon(Icons.person_outline_rounded, 'حسابي',
                  () => _enter(const AccountPage())),
            ],
          ),
          Semantics(
            label: 'وصّلي',
            image: true,
            child: Image.asset(
              kWasallyLogoLightAsset,
              height: 42,
              fit: BoxFit.contain,
              excludeFromSemantics: true,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
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
        // تغيير العنوان موجود في الرئيسية.
        onTap: () => _enter(null, 0),
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
          height: 50,
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
              Icon(Icons.search_rounded, color: AppColors.muted.withValues(alpha: 0.9), size: 28),
              const SizedBox(width: AppSpacing.lg),
            ],
          ),
        ),
      ),
    );
  }

  // ───────────────────────── البانر ─────────────────────────

  Widget _banner() {
    return Stack(
      children: [
        // امتداد لون الهيدر خلف نصف البانر العلوي زي التصميم المرجعي.
        Container(height: 64, color: AppColors.purpleDeep),
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xxs, AppSpacing.md, 0),
          child: AspectRatio(
            aspectRatio: 2.2,
            child: Material(
              key: const Key('entry-banner'),
              color: const Color(0xFF2E1774),
              elevation: 6,
              shadowColor: AppColors.purpleDeep.withValues(alpha: 0.35),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppRadius.xl),
                side: BorderSide(color: AppColors.orange.withValues(alpha: 0.75), width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => _enter(const StoreDirectoryPage()),
                child: Row(
                  textDirection: TextDirection.ltr,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      flex: 6,
                      child: Image.asset(
                        kEntryBannerAsset,
                        fit: BoxFit.cover,
                        alignment: Alignment.centerLeft,
                        excludeFromSemantics: true,
                      ),
                    ),
                    Expanded(
                      flex: 5,
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(AppSpacing.lg, AppSpacing.md, AppSpacing.xs, AppSpacing.md),
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
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: AppSpacing.md),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                              decoration: BoxDecoration(
                                color: const Color(0xCC5A3524),
                                borderRadius: BorderRadius.circular(AppRadius.pill),
                              ),
                              child: const Text(
                                'اطلب الآن',
                                maxLines: 1,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: AppTypography.bodySmall,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ───────────────────────── كروت الخدمات ─────────────────────────

  Widget _serviceCard({
    required String title,
    required String subtitle,
    required String action,
    required IconData icon,
    required String asset,
    required VoidCallback onTap,
    required double height,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Material(
        elevation: 4,
        shadowColor: AppColors.ink.withValues(alpha: 0.14),
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
          child: SizedBox(
            height: height,
            child: Row(
              textDirection: TextDirection.ltr,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // الصورة الواقعية ملاصقة لمحتوى الكارت (الصورة نفسها
                // بتتلاشى للأبيض ناحية النص زي التصميم المرجعي).
                Expanded(
                  flex: 11,
                  child: Image.asset(
                    asset,
                    key: ValueKey<String>('entry-art-$title'),
                    fit: BoxFit.cover,
                    alignment: Alignment.centerLeft,
                    excludeFromSemantics: true,
                  ),
                ),
                Expanded(
                  flex: 10,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(
                        AppSpacing.md, AppSpacing.md, AppSpacing.xs, AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Container(
                              width: 36,
                              height: 36,
                              decoration: BoxDecoration(
                                gradient: const LinearGradient(
                                  begin: Alignment.topRight,
                                  end: Alignment.bottomLeft,
                                  colors: [AppColors.orangeLight, AppColors.orangeDeep],
                                ),
                                borderRadius: BorderRadius.circular(AppRadius.sm),
                              ),
                              child: Icon(icon, color: Colors.white, size: 22),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Expanded(
                              child: Text(
                                title,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: AppColors.purpleDeep,
                                  fontSize: 18,
                                  height: 1.15,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          subtitle,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.muted,
                            fontSize: AppTypography.caption,
                            height: 1.25,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          height: 38,
                          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [AppColors.orangeLight, AppColors.orange, AppColors.orangeDeep],
                            ),
                            borderRadius: BorderRadius.circular(AppRadius.pill),
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.orange.withValues(alpha: 0.28),
                                blurRadius: 8,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Flexible(
                                child: Text(
                                  action,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: AppTypography.bodySmall,
                                    fontWeight: FontWeight.w900,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Icon(Icons.chevron_left_rounded, color: Colors.white, size: 20),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// ارتفاع الكارت بيتبع عرض الشاشة وحجم الخط من إعدادات الهاتف.
  double _cardHeight(BuildContext context, double width) {
    final scale = MediaQuery.textScalerOf(context);
    final content = scale.scale(18) * 1.15 * 2 +
        AppSpacing.xs +
        scale.scale(AppTypography.caption) * 1.25 * 2 +
        AppSpacing.sm +
        38 +
        AppSpacing.md * 2;
    final art = width * 0.36;
    return art > content ? art : content;
  }

  Widget _staffNav() => CurvedNavBar(
        index: 2,
        onTap: (i) {
          switch (i) {
            case 1:
              _openNotifications();
            case 3:
              _enter(const AccountPage());
            default:
              // لوحتي والرئيسية: لوحة الدور (نفس السلوك السابق).
              _enter();
          }
        },
        items: const [
          AppNavItem(icon: Icons.dashboard_outlined, selectedIcon: Icons.dashboard_rounded, label: 'لوحتي'),
          AppNavItem(icon: Icons.notifications_none_rounded, selectedIcon: Icons.notifications_rounded, label: 'الإشعارات'),
          AppNavItem(icon: Icons.home_outlined, selectedIcon: Icons.home_rounded, label: 'الرئيسية'),
          AppNavItem(icon: Icons.person_outline_rounded, selectedIcon: Icons.person_rounded, label: 'حسابي'),
        ],
      );

  @override
  Widget build(BuildContext context) {
    if (_entered) return _dashboard;

    final width = MediaQuery.sizeOf(context).width;
    final cardHeight = _cardHeight(context, width - AppSpacing.md * 2);
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: ListView(
              key: const Key('entry-list'),
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              children: [
                _banner(),
                const SizedBox(height: AppSpacing.lg),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _serviceCard(
                        title: 'خدمة وصّلي ع السريع',
                        subtitle: 'طلباتك اليومية وتوصيلها بسرعة',
                        action: 'اطلب الآن',
                        icon: Icons.bolt_rounded,
                        asset: kEntryQuickAsset,
                        height: cardHeight,
                        onTap: () => _enter(const QuickOrderCreatePage()),
                      ),
                      _serviceCard(
                        title: 'تصفح العروض',
                        subtitle: 'أقوى الخصومات والعروض الحصرية',
                        action: 'شاهد العروض',
                        icon: Icons.percent_rounded,
                        asset: kEntryOffersAsset,
                        height: cardHeight,
                        onTap: () => _enter(const HomePage(offersOnly: true)),
                      ),
                      _serviceCard(
                        title: 'تصفح المحلات',
                        subtitle: 'اكتشف جميع المحلات والأصناف',
                        action: 'استعرض المحلات',
                        icon: Icons.storefront_rounded,
                        asset: kEntryStoresAsset,
                        height: cardHeight,
                        onTap: () => _enter(const StoreDirectoryPage()),
                      ),
                      if (!_isCustomer)
                        FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: AppColors.purple),
                          onPressed: () => _enter(),
                          icon: const Icon(Icons.dashboard_customize_outlined),
                          label: Text(widget.dashboardLabel ?? 'افتح لوحتي'),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _isCustomer
          // Approved order: السلة، طلباتي، الرئيسية، حسابي.
          ? CustomerBottomNav(currentTab: 0, onTab: (tab) => _enter(null, tab))
          : _staffNav(),
    );
  }
}
