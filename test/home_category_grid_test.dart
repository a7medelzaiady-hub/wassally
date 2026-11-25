import 'package:city_store/models/home_category.dart';
import 'package:city_store/widgets/home_category_grid.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Home shortcuts map to actual store categories, not English UI IDs', () {
    expect(homeCategories.length, 8);
    expect(homeCategories.map((e) => e.id).toSet().length, 8);

    expect(matchesDirectoryCategory('restaurants', 'مطاعم'), isTrue);
    expect(matchesDirectoryCategory('market', 'سوبرماركت'), isTrue);
    expect(matchesDirectoryCategory('market', 'بقالة'), isTrue);
    expect(matchesDirectoryCategory('market', 'خضار وفاكهة'), isTrue);
    expect(matchesDirectoryCategory('market', 'مطاعم'), isFalse);
    expect(matchesDirectoryCategory('meat', 'لحوم ودواجن'), isTrue);
    expect(matchesDirectoryCategory('bakery', 'مخبوزات وحلويات'), isTrue);
    expect(matchesDirectoryCategory('pharmacy', 'صيدليات'), isTrue);
    expect(matchesDirectoryCategory('roastery', 'محمصات وعطارة'), isTrue);
    expect(matchesDirectoryCategory('cafe', 'كافيه ومشروبات'), isTrue);
    expect(matchesDirectoryCategory('flowers', 'ورد وهدايا'), isTrue);

    // Chip filters from the directory itself still work without mapping.
    expect(matchesDirectoryCategory('مطاعم', 'مطاعم'), isTrue);
    expect(matchesDirectoryCategory('مطاعم', 'بقالة'), isFalse);
    expect(matchesDirectoryCategory('صيدليات', 'صيدلية'), isTrue);
    for (final item in homeCategories) {
      expect(item.photoUrl, startsWith('https://images.unsplash.com/photo-'));
      expect(item.storeCategories, isNotEmpty);
    }
  });

  testWidgets('Four category photos per row on a 320px phone with working taps',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    String? chosen = 'none';
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: HomeCategoryGrid(
                loadPhotos: false, // no remote image dependency in the test
                onSelected: (id) => chosen = id,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('أقسامنا المختلفة'), findsOneWidget);
    expect(find.byKey(const Key('home-category-grid')), findsOneWidget);
    expect(find.byKey(const Key('home-category-$kAllCategoriesId')), findsOneWidget);
    for (final item in homeCategories) {
      expect(find.byKey(Key('home-category-${item.id}')), findsOneWidget);
    }
    // «الكل» is the first card of the first row (rightmost in RTL).
    final row = [
      for (final id in [kAllCategoriesId, 'restaurants', 'market', 'meat'])
        tester.getTopLeft(find.byKey(Key('home-category-$id'))),
    ];
    expect(row[1].dy, row[0].dy);
    expect(row[2].dy, row[0].dy);
    expect(row[3].dy, row[0].dy);
    expect(row[0].dx, greaterThan(row[1].dx));
    final nextRowY = tester.getTopLeft(
      find.byKey(const Key('home-category-bakery')),
    ).dy;
    expect(nextRowY, greaterThan(row[0].dy));
    expect(tester.takeException(), isNull);

    await tester.tap(find.byKey(const Key('home-category-market')));
    expect(chosen, 'market');
    await tester.tap(find.byKey(const Key('home-category-$kAllCategoriesId')));
    expect(chosen, isNull, reason: '«الكل» يفتح كل المحلات بدون تصفية');
  });

  testWidgets('الأقسام تتحمل تكبير الخط 1.3 بدون قص أو overflow', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
    await tester.pumpWidget(MaterialApp(
      home: MediaQuery(
        data: const MediaQueryData(
          size: Size(320, 900),
          textScaler: TextScaler.linear(1.3),
        ),
        child: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: SingleChildScrollView(
              child: HomeCategoryGrid(
                loadPhotos: false,
                selectedId: 'market',
                highlightSelection: true,
                onSelected: (_) {},
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
