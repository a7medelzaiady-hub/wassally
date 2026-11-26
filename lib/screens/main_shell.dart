import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/app_role.dart';
import '../services/role_service.dart';

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

  // كل تبويب بيتبني أول مرة العميل يفتحه بس، وبعدها بيفضل محفوظ.
  // قبل كده IndexedStack كان بيبني الأربع صفحات مع فتح التطبيق، فصفحة «طلباتي»
  // كانت بتفتح مستمع على آخر 50 طلب (قراءات Firestore) حتى لو العميل ما فتحهاش.
  static const _pages = <Widget>[
    HomePage(),
    _LazyTab(tab: 1, child: CartPage()),
    _LazyTab(tab: 2, child: OrdersPage()),
    _LazyTab(tab: 3, child: AccountPage()),
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
          // السلة ليها زرار أساسي تحت، فالزرار العايم بيزحمها.
          floatingActionButton: index == 3 || index == 1
              ? null
              : const FeedbackFab(allowOrderIssue: true),
          body: Stack(
            children: [
              IndexedStack(index: index, children: _pages),
              if (index != 1 &&
                  Navigator.of(context).canPop() &&
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
          // Same approved bar as the entry page and inner shopping pages.
          bottomNavigationBar: CustomerBottomNav(
            currentTab: index,
            onTab: (tab) => shellTab.value = tab,
          ),
        ),
        );
      },
    );
  }
}

/// بيأجّل بناء التبويب لحد أول مرة يتفتح فيها (shellTab == tab)، وبعدها يفضل مبني.
class _LazyTab extends StatefulWidget {
  final int tab;
  final Widget child;
  const _LazyTab({required this.tab, required this.child});

  @override
  State<_LazyTab> createState() => _LazyTabState();
}

class _LazyTabState extends State<_LazyTab> {
  bool _opened = false;

  @override
  void initState() {
    super.initState();
    _opened = shellTab.value == widget.tab;
    shellTab.addListener(_onTab);
  }

  void _onTab() {
    if (!_opened && shellTab.value == widget.tab) {
      setState(() => _opened = true);
      shellTab.removeListener(_onTab);
    }
  }

  @override
  void dispose() {
    shellTab.removeListener(_onTab);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _opened ? widget.child : const SizedBox.shrink();
}
