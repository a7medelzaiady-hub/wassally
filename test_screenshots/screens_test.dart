import 'package:city_store/screens/categories_landing_page.dart';
import 'package:city_store/screens/quick_order_create_page.dart';
import 'package:city_store/screens/store_directory_page.dart';
import 'package:city_store/services/catalog_sync.dart';
import 'package:city_store/widgets/curved_nav_bar.dart';
import 'package:city_store/widgets/home_category_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'harness.dart';

List<CatalogDoc> _stores() => [
      for (final (i, name, category) in [
        (1, 'الزيادى لزيوت السيارات', 'زيوت سيارات'),
        (2, 'فواكه وخضروات', 'سوبرماركت'),
        (3, 'مطعم الأصيل', 'مطاعم'),
        (4, 'ألبان المحطة', 'ألبان'),
        (5, 'صيدلية الشفاء', 'صيدليات'),
        (6, 'مخبز النور', 'مخبوزات'),
      ])
        CatalogDoc('s$i', {
          'name': name,
          'category': category,
          'active': true,
          'isOpen': i != 4,
          'order': i,
          'time': '15-20 د',
          'ratingSum': 4.5 * 2,
          'ratingCount': 2,
          'products': [
            for (var p = 0; p < i; p++) {'id': 'p$p', 'name': 'منتج $p', 'price': 10},
          ],
        }),
    ];

void main() {
  testWidgets('entry customer 390', (tester) async {
    await shoot(tester, 'entry_customer_390x844', const CustomerEntry());
  });

  testWidgets('entry customer small 320', (tester) async {
    await shoot(tester, 'entry_customer_320x640', const CustomerEntry(),
        size: const Size(320, 640));
  });

  testWidgets('entry customer large text', (tester) async {
    await shoot(tester, 'entry_customer_390_text130', const CustomerEntry(),
        textScale: 1.3);
  });

  testWidgets('entry store owner', (tester) async {
    await shoot(
      tester,
      'entry_owner_390x844',
      const CustomerEntry(
        dashboard: SizedBox.shrink(),
        dashboardLabel: 'لوحة المحل',
      ),
    );
  });

  testWidgets('shopping page top', (tester) async {
    await shoot(
      tester,
      'shopping_top_390x844',
      StoreDirectoryPage(loader: () async => _stores(), showBanners: false),
      before: (tester) async {
        await tester.pump(const Duration(milliseconds: 100));
      },
    );
  });

  testWidgets('shopping page scrolled', (tester) async {
    await shoot(
      tester,
      'shopping_scrolled_390x844',
      StoreDirectoryPage(loader: () async => _stores(), showBanners: false),
      before: (tester) async {
        await tester.pump(const Duration(milliseconds: 100));
        await tester.drag(find.byKey(const Key('directory-scroll')), const Offset(0, -260));
        await tester.pumpAndSettle();
      },
    );
  });

  testWidgets('home categories with all', (tester) async {
    await shoot(
      tester,
      'home_categories_390',
      Scaffold(
        body: SingleChildScrollView(
          child: HomeCategoryGrid(
            loadPhotos: false,
            onSelected: (_) {},
          ),
        ),
        bottomNavigationBar: const CustomerBottomNav(currentTab: 0),
      ),
      size: const Size(390, 560),
    );
  });

  testWidgets('quick order create', (tester) async {
    await shoot(
      tester,
      'quick_create_390x844',
      const QuickOrderCreatePage(prefillFromAccount: false),
    );
  });

  testWidgets('quick order create scrolled', (tester) async {
    await shoot(
      tester,
      'quick_create_scrolled_390x844',
      const QuickOrderCreatePage(prefillFromAccount: false),
      before: (tester) async {
        await tester.drag(find.byKey(const Key('quick-create-list')), const Offset(0, -700));
        await tester.pump(const Duration(seconds: 1));
      },
    );
  });
}
