import 'package:flutter/material.dart';

import '../services/cart_book.dart';
import '../services/navigation.dart';
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
  const CurvedNavBar({
    super.key,
    required this.index,
    required this.onTap,
    required this.items,
  });

  static const double barHeight = 66;

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

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Container(
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
              Expanded(
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
              ),
          ],
        ),
      ),
    );
  }
}

/// ترتيب أزرار العميل المعتمد (من اليمين لليسار في RTL):
/// السلة، طلباتي، الرئيسية، حسابي. القيم هي أرقام تبويبات [shellTab].
const customerNavTabs = <int>[1, 2, 0, 3];

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
        onTap: (i) {
          final tab = customerNavTabs[i];
          if (onTab != null) {
            onTab!(tab);
          } else {
            openCustomerTab(context, tab);
          }
        },
        items: [
          AppNavItem(
            icon: Icons.shopping_cart_outlined,
            selectedIcon: Icons.shopping_cart_rounded,
            label: 'السلة',
            badge: carts.totalItems,
          ),
          const AppNavItem(
            icon: Icons.receipt_long_outlined,
            selectedIcon: Icons.receipt_long_rounded,
            label: 'طلباتي',
          ),
          const AppNavItem(
            icon: Icons.home_outlined,
            selectedIcon: Icons.home_rounded,
            label: 'الرئيسية',
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
