import 'package:flutter/material.dart';

import '../services/cart_book.dart';
import '../services/navigation.dart';
import '../screens/notifications_page.dart';
import '../theme/app_tokens.dart';

class AppNavItem {
  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final int badge;
  const AppNavItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.badge = 0,
  });
}

/// شريط التنقل السفلي الموحد لكل التطبيق (AppBottomNavigation).
///
/// نفس الارتفاع والألوان والأيقونات وحجم الخط وأسلوب تمييز الصفحة النشطة
/// في كل مكان: مؤشر بنفسجي فاتح خلف الأيقونة النشطة واسمها بالبنفسجي.
/// [index] = -1 لما الصفحة الحالية مش واحدة من تبويبات الشريط.
class CurvedNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  final List<AppNavItem> items;

  /// زر كبير بارز في النص (السلة) زي التطبيقات المشهورة.
  final int? centerIndex;
  const CurvedNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
    this.centerIndex,
  });

  static const double barHeight = 64;
  static const double _bump = 22;
  static const double _centerSize = 62;

  Widget _centerButton(AppNavItem item, bool selected, VoidCallback onTap) {
    final icon = Icon(item.selectedIcon, color: Colors.white, size: 30);
    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      excludeSemantics: true,
      child: GestureDetector(
        key: ValueKey<String>('nav-${item.label}'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: _centerSize,
              height: _centerSize,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [AppColors.orangeLight, AppColors.orangeDeep],
                ),
                border: Border.all(color: Colors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.orange.withValues(alpha: 0.35),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Center(
                child: item.badge <= 0
                    ? icon
                    : Badge(
                        backgroundColor: AppColors.purpleDeep,
                        label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
                        child: icon,
                      ),
              ),
            ),
            const SizedBox(height: 2),
            Text(
              item.label,
              maxLines: 1,
              style: TextStyle(
                fontSize: AppTypography.label,
                height: 1.15,
                fontWeight: FontWeight.w900,
                color: selected ? AppColors.orangeDeep : AppColors.orange,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _icon(AppNavItem item, bool selected) {
    final icon = Icon(
      selected ? item.selectedIcon : item.icon,
      color: selected ? AppColors.purple : AppColors.muted,
      size: 24,
    );
    final withBadge = item.badge <= 0
        ? icon
        : Badge(
            backgroundColor: AppColors.orange,
            label: Text(item.badge > 99 ? '99+' : '${item.badge}'),
            child: icon,
          );
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: 58,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: selected ? AppColors.purpleSoft : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: withBadge,
    );
  }

  Widget _item(int i) => Expanded(
        child: Semantics(
          button: true,
          selected: i == index,
          label: items[i].label,
          excludeSemantics: true,
          child: InkResponse(
            key: ValueKey<String>('nav-${items[i].label}'),
            onTap: () => onTap(i),
            radius: 36,
            highlightShape: BoxShape.circle,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _icon(items[i], i == index),
                const SizedBox(height: 3),
                // Stays on one line even with a large system font.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    items[i].label,
                    maxLines: 1,
                    style: TextStyle(
                      fontSize: AppTypography.label,
                      height: 1.15,
                      fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                      color: i == index ? AppColors.purple : AppColors.muted,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final center = centerIndex;
    final bar = Container(
      padding: EdgeInsets.only(bottom: bottom),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        boxShadow: [
          BoxShadow(color: Color(0x161E1638), blurRadius: 16, offset: Offset(0, -4)),
        ],
      ),
      child: SizedBox(
        height: barHeight,
        child: Row(
          children: [
            for (var i = 0; i < items.length; i++)
              if (i == center)
                const Expanded(child: SizedBox.shrink())
              else
                _item(i),
          ],
        ),
      ),
    );
    if (center == null) return bar;
    // The raised button sits inside the widget's bounds (transparent area on
    // top) so its whole circle receives taps.
    return SizedBox(
      height: barHeight + bottom + _bump,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(left: 0, right: 0, bottom: 0, child: bar),
          Positioned(
            top: 0,
            bottom: bottom + 2,
            left: 0,
            right: 0,
            child: Row(
              children: [
                for (var i = 0; i < items.length; i++)
                  Expanded(
                    child: i == center
                        ? Align(
                            alignment: Alignment.topCenter,
                            child: _centerButton(items[i], i == index, () => onTap(i)),
                          )
                        : const IgnorePointer(child: SizedBox.expand()),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// رقم خاص لزر الإشعارات (صفحة مستقلة، مش تبويب في [shellTab]).
const kNotificationsNavTab = 4;

/// ترتيب أزرار العميل (من اليمين لليسار في RTL) زي التصميم المرجعي:
/// الرئيسية، طلباتي، السلة (كبيرة في النص)، الإشعارات، حسابي.
const customerNavTabs = <int>[0, 2, 1, kNotificationsNavTab, 3];

/// شريط العميل الموحد، يُستخدم في الصفحة الأساسية وصفحات التسوق الداخلية.
/// [currentTab] = رقم التبويب النشط، أو null لو الصفحة صفحة داخلية.
class CustomerBottomNav extends StatelessWidget {
  const CustomerBottomNav({super.key, required this.currentTab, this.onTab});

  final int? currentTab;

  /// الافتراضي: يرجع لجذر التطبيق ويفتح التبويب المطلوب.
  final ValueChanged<int>? onTab;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: carts,
      builder: (context, _) => CurvedNavBar(
        index: currentTab == null ? -1 : customerNavTabs.indexOf(currentTab!),
        centerIndex: 2,
        onTap: (i) {
          final tab = customerNavTabs[i];
          if (tab == kNotificationsNavTab) {
            pushOnce<void>(context, 'notifications', (_) => const NotificationsPage());
          } else if (onTab != null) {
            onTab!(tab);
          } else {
            openCustomerTab(context, tab);
          }
        },
        items: [
          const AppNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'الرئيسية',
          ),
          const AppNavItem(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: 'طلباتي',
          ),
          AppNavItem(
            icon: Icons.shopping_cart_outlined,
            selectedIcon: Icons.shopping_cart_rounded,
            label: 'السلة',
            badge: carts.totalItems,
          ),
          const AppNavItem(
            icon: Icons.notifications_none_rounded,
            selectedIcon: Icons.notifications_rounded,
            label: 'الإشعارات',
          ),
          const AppNavItem(
            icon: Icons.person_outline_rounded,
            selectedIcon: Icons.person_rounded,
            label: 'حسابي',
          ),
        ],
      ),
    );
  }
}

/// الشريط بيظهر في صفحات التسوق الداخلية للعميل فقط، مش لأدوار تانية
/// لوحتهم مختلفة، ومش في شاشات الدخول.
class CustomerPageNav extends StatelessWidget {
  const CustomerPageNav({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: customerShellAvailable,
        builder: (context, available, _) => available
            ? const CustomerBottomNav(currentTab: null)
            : const SizedBox.shrink(),
      );
}
