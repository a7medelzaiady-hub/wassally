import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/role_service.dart';

import '../services/cart_book.dart';
import '../services/cart_model.dart';
import '../services/navigation.dart';
import '../services/performance_monitor.dart';
import '../widgets/curved_nav_bar.dart';
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
        PerformanceMonitor.screenOpened(switch (index) {
          0 => 'home',
          1 => 'cart',
          2 => 'orders',
          3 => 'account',
          _ => 'other',
        });
        return PopScope(
          canPop: index == 0,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) shellTab.value = 0;
          },
          child: Scaffold(
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
          bottomNavigationBar: ListenableBuilder(
            listenable: Listenable.merge([cart, carts]),
            builder: (context, _) {
              // تبديل موضعي الرئيسية والسلة مع الحفاظ على طلباتي وحسابي.
              // من اليمين لليسار: الرئيسية، طلباتي، السلة، حسابي.
              const map = [0, 2, 1, 3];
              return CurvedNavBar(
                index: map.indexOf(index),
                onTap: (i) {
                  shellTab.value = map[i];
                },
                items: [
                  const AppNavItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home_rounded,
                    label: 'الرئيسية',
                  ),
                  const AppNavItem(
                    icon: Icons.receipt_long_outlined,
                    selectedIcon: Icons.receipt_long,
                    label: 'طلباتي',
                  ),
                  AppNavItem(
                    icon: Icons.shopping_cart_outlined,
                    selectedIcon: Icons.shopping_cart,
                    label: 'السلة',
                    badge: carts.totalItems,
                  ),
                  const AppNavItem(
                    icon: Icons.person_outline,
                    selectedIcon: Icons.person,
                    label: 'حسابي',
                  ),
                ],
              );
            },
          ),
        ),
        );
      },
    );
  }
}
