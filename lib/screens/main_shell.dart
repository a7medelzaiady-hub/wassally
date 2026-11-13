import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/role_service.dart';

import '../services/cart_model.dart';
import '../services/navigation.dart';
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
          floatingActionButton: const FeedbackFab(allowOrderIssue: true),
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
            listenable: cart,
            builder: (context, _) {
              return NavigationBar(
                backgroundColor: Colors.white,
                surfaceTintColor: Colors.transparent,
                indicatorColor: Colors.transparent,
                selectedIndex: index,
                onDestinationSelected: (i) => shellTab.value = i,
                destinations: [
                  const NavigationDestination(
                    icon: Icon(Icons.home_outlined),
                    selectedIcon: Icon(Icons.home_rounded),
                    label: 'الرئيسية',
                  ),
                  NavigationDestination(
                    icon: Badge(
                      isLabelVisible: cart.count > 0,
                      label: Text('${cart.count}'),
                      child: const Icon(Icons.shopping_cart_outlined),
                    ),
                    selectedIcon: Badge(
                      isLabelVisible: cart.count > 0,
                      label: Text('${cart.count}'),
                      child: const Icon(Icons.shopping_cart),
                    ),
                    label: 'السلة',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.receipt_long_outlined),
                    selectedIcon: Icon(Icons.receipt_long),
                    label: 'طلباتي',
                  ),
                  const NavigationDestination(
                    icon: Icon(Icons.person_outline),
                    selectedIcon: Icon(Icons.person),
                    label: 'حسابي',
                  ),
                ],
              );
            },
          ),
        );
      },
    );
  }
}
