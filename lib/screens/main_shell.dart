import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/role_service.dart';
import '../services/cart_model.dart';
import '../services/navigation.dart';
import '../theme/brand.dart';
import '../widgets/feedback_fab.dart';
import 'account_page.dart';
import 'cart_page.dart';
import 'home_page.dart';
import 'orders_page.dart';

class MainShell extends StatelessWidget {
  const MainShell({super.key});

  static const _pages = <Widget>[
    HomePage(),
    CartPage(),
    OrdersPage(),
    AccountPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: shellTab,
      builder: (context, index, _) {
        return Scaffold(
          floatingActionButton: index == 3
              ? null
              : const FeedbackFab(allowOrderIssue: true),
          body: Stack(
            children: [
              IndexedStack(index: index, children: _pages),
              if (Navigator.of(context).canPop() &&
                  (RoleService.cachedFor(
                            FirebaseAuth.instance.currentUser?.uid ?? '',
                          )?.role ??
                          AppRole.customer) !=
                      AppRole.customer)
                PositionedDirectional(
                  start: 14,
                  bottom: 12,
                  child: FilledButton.icon(
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.dashboard_outlined, size: 18),
                    label: const Text('لوحتي'),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      elevation: 4,
                    ),
                  ),
                ),
            ],
          ),
          bottomNavigationBar: _WasallyBottomBar(index: index),
        );
      },
    );
  }
}

class _WasallyBottomBar extends StatelessWidget {
  static const _navPalette = AppPalette.purple;
  final int index;
  const _WasallyBottomBar({required this.index});

  void _openOffers() {
    shellTab.value = 0;
    homeOffersRequest.value++;
  }

  Widget _item({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    bool selected = false,
  }) {
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: SizedBox(
            height: 66,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22,
                    color: selected ? _navPalette.primary : Brand.palette.muted),
                const SizedBox(height: 3),
                Text(
                  label,
                  maxLines: 1,
                  style: TextStyle(
                    fontSize: 10.5,
                    height: 1.1,
                    fontWeight: selected ? FontWeight.w900 : FontWeight.w700,
                    color: selected ? _navPalette.primary : Brand.palette.muted,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 112,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            return Stack(
              clipBehavior: Clip.none,
              children: [
                PositionedDirectional(
                  start: 10,
                  end: 10,
                  bottom: 14,
                  child: Container(
                    height: 68,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(28),
                      border: Border.all(
                        color: _navPalette.primary.withValues(alpha: 0.24),
                        width: 1.2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _navPalette.primaryDark.withValues(alpha: 0.13),
                          blurRadius: 18,
                          offset: const Offset(0, 7),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        _item(
                          icon: Icons.person_outline_rounded,
                          label: 'حسابي',
                          selected: index == 3,
                          onTap: () => shellTab.value = 3,
                        ),
                        _item(
                          icon: Icons.receipt_long_outlined,
                          label: 'طلباتي',
                          selected: index == 2,
                          onTap: () => shellTab.value = 2,
                        ),
                        const Expanded(child: SizedBox()),
                        const Expanded(child: SizedBox()),
                        _item(
                          icon: Icons.local_offer_outlined,
                          label: 'العروض',
                          selected: false,
                          onTap: _openOffers,
                        ),
                      ],
                    ),
                  ),
                ),
                // الرئيسية بارزة من أعلى الشريط.
                Positioned(
                  left: (width - 68) / 2,
                  top: 0,
                  child: _GradientNavButton(
                    size: 68,
                    icon: Icons.home_rounded,
                    label: 'الرئيسية',
                    selected: index == 0,
                    onTap: () => shellTab.value = 0,
                    hangsBelow: false,
                  ),
                ),
                // السلة تتدلّى من أسفل جسم الشريط بإطار متدرج، والعداد حيّ.
                Positioned(
                  left: width * 0.30 - 29,
                  bottom: 0,
                  child: ListenableBuilder(
                    listenable: cart,
                    builder: (context, _) => _GradientNavButton(
                      size: 58,
                      icon: Icons.shopping_bag_rounded,
                      label: 'سلتي',
                      badgeText: cart.count > 0
                          ? (cart.count > 99 ? '99+' : '${cart.count}')
                          : null,
                      selected: index == 1,
                      onTap: () => shellTab.value = 1,
                      hangsBelow: true,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _GradientNavButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final String label;
  final bool selected;
  final bool hangsBelow;
  final String? badgeText;
  final VoidCallback onTap;

  const _GradientNavButton({
    required this.size,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    required this.hangsBelow,
    this.badgeText,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              colors: [Color(0xFF9F67FF), Color(0xFF5B21B6)],
              begin: Alignment.topRight,
              end: Alignment.bottomLeft,
            ),
            boxShadow: [
              BoxShadow(
                color: AppPalette.purple.primary.withValues(alpha: selected ? 0.34 : 0.22),
                blurRadius: selected ? 17 : 12,
                offset: Offset(0, hangsBelow ? -2 : 4),
              ),
            ],
          ),
          child: Container(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const LinearGradient(
                colors: [Color(0xFF9F67FF), Color(0xFF7C3AED)],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.72),
                width: 1.2,
              ),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.center,
              children: [
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(icon, color: Colors.white, size: size * 0.39),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: hangsBelow ? 9.5 : 10,
                        height: 1,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ],
                ),
                if (badgeText != null)
                  PositionedDirectional(
                    top: 1,
                    start: 0,
                    child: Container(
                      constraints: const BoxConstraints(minWidth: 17, minHeight: 17),
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppPalette.purple.primaryDark, width: 1),
                      ),
                      child: Text(
                        badgeText!,
                        style: TextStyle(
                          color: AppPalette.purple.primaryDark,
                          fontSize: 9,
                          fontWeight: FontWeight.w900,
                        ),
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
}
