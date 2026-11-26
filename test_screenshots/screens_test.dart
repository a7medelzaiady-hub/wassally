import 'package:city_store/screens/admin_navigation_page.dart';
import 'package:city_store/models/product.dart';
import 'package:city_store/screens/cart_page.dart';
import 'package:city_store/utils/cart_share.dart';
import 'package:city_store/widgets/order_receipt_sheet.dart';
import 'package:city_store/screens/my_carts_page.dart';
import 'package:city_store/services/cart_book.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:city_store/screens/categories_landing_page.dart';
import 'package:city_store/screens/user_guide_page.dart';
import 'package:city_store/screens/onboarding_page.dart';
import 'package:city_store/screens/quick_order_create_page.dart';
import 'package:city_store/screens/store_directory_page.dart';
import 'package:city_store/services/catalog_sync.dart';
import 'package:city_store/widgets/curved_nav_bar.dart';
import 'package:city_store/widgets/home_category_grid.dart';
import 'package:city_store/widgets/offer_carousel.dart';
import 'package:city_store/widgets/quick_order_promo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
    await shoot(tester, 'entry_customer_390x844', const CustomerEntry(showInviteCode: true));
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

  testWidgets('quick order create voice', (tester) async {
    await shoot(
      tester,
      'quick_create_voice_390x844',
      const QuickOrderCreatePage(prefillFromAccount: false, initialMethod: QuickOrderMethod.voice),
    );
  });

  testWidgets('quick order create write', (tester) async {
    await shoot(
      tester,
      'quick_create_write_390x844',
      const QuickOrderCreatePage(prefillFromAccount: false, initialMethod: QuickOrderMethod.write),
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

  testWidgets('cart empty tab', (tester) async {
    await shoot(tester, 'cart_empty_390x844', const Scaffold(
      body: CartPage(),
      bottomNavigationBar: CustomerBottomNav(currentTab: 1),
    ));
  });

  testWidgets('cart empty inner', (tester) async {
    await shoot(tester, 'cart_inner_390x844', const Scaffold(body: CartPage(showBackButton: true)));
  });

  testWidgets('cart with items + my carts', (tester) async {
    // ignore: invalid_use_of_visible_for_testing_member
    SharedPreferences.setMockInitialValues({});
    carts.clearAll();
    cart.add(const Product('بطاطس', 33), storeId: 'veg', storeName: 'فواكه وخضروات', qty: 5);
    carts.switchTo('ph');
    cart.add(const Product('فيتامين سي', 45), storeId: 'ph', storeName: 'صيدلية الشفاء');
    cart.add(const Product('كمامات (علبة)', 30), storeId: 'ph', storeName: 'صيدلية الشفاء');
    await shoot(tester, 'cart_items_390x844', const Scaffold(
      body: CartPage(),
      bottomNavigationBar: CustomerBottomNav(currentTab: 1),
    ));
    await shoot(tester, 'my_carts_390x844', const MyCartsPage(allowGrouping: true));
    await shoot(tester, 'cart_thermal_receipt_390x844',
        Scaffold(backgroundColor: const Color(0xFFE9E9EC), body: OrderReceiptSheet(receipt: buildCartReceipt(cart))));
    cart.markSubmitted('order_shot');
    await shoot(tester, 'cart_submitted_390x844', const Scaffold(
      body: CartPage(),
      bottomNavigationBar: CustomerBottomNav(currentTab: 1),
    ));
    await shoot(tester, 'my_carts_submitted_390x844', const MyCartsPage(allowGrouping: true));
    carts.clearAll();
  });

  testWidgets('user guide', (tester) async {
    await shoot(tester, 'user_guide_390x844', const UserGuidePage());
  });

  testWidgets('admin tools', (tester) async {
    await shoot(tester, 'admin_tools_390x844', const AdminNavigationPage());
  });

  testWidgets('home promo and offer carousel', (tester) async {
    await shoot(
      tester,
      'home_promo_carousel_390',
      Scaffold(
        body: ListView(padding: const EdgeInsets.all(16), children: [
          PromoCarousel(autoPlay: false, slides: [QuickOrderPromo(onTap: () {}), PhotoOrderPromo(onTap: () {})]),
          const SizedBox(height: 12),
          SizedBox(height: 270, child: PhotoOrderPromo(onTap: () {})),
          const SizedBox(height: 18),
          OfferCarousel(autoPlay: false, loadImages: false, slides: [
            OfferSlide(name: 'خيار', storeName: 'فواكه وخضروات', price: 13.5, oldPrice: 15, onTap: () {}),
            OfferSlide(name: 'بطاطس', storeName: 'فواكه وخضروات', price: 33, offerText: 'هدية مع الطلب', onTap: () {}),
          ]),
        ]),
      ),
      size: const Size(390, 900),
    );
  });

  for (var i = 0; i < 3; i++) {
    testWidgets('onboarding step $i', (tester) async {
      await shoot(tester, 'onboarding_${i + 1}_390x844', OnboardingPage(onDone: () {}), before: (tester) async {
        for (var k = 0; k < i; k++) {
          await tester.tap(find.byKey(const Key('onboarding-next')));
          await tester.pumpAndSettle();
        }
      });
    });
  }
}
