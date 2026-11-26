import 'package:city_store/screens/store_directory_page.dart';
import 'package:city_store/services/catalog_sync.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

List<CatalogDoc> _testStores() => [
      CatalogDoc('open', {
        'name': 'بقالة الفرح',
        'active': true,
        'isOpen': true,
        'category': 'سوبرماركت',
        'products': [{'name': 'لبن', 'price': 10}],
      }),
      CatalogDoc('closed', {
        'name': 'مطعم الساحة',
        'active': true,
        'isOpen': false,
        'category': 'سوبرماركت',
        'products': [{'name': 'زيت', 'price': 20}],
      }),
    ];

void main() {
  testWidgets('حالة المحل لا تتغير حسب عدد المنتجات', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: StoreDirectoryPage(
        loader: () async => _testStores(),
        showBanners: false,
      ),
    ));
    await tester.pumpAndSettle();

    // وجود منتجات في المحلين لا يبدّل الحالة بشارة العدد.
    expect(find.text('مفتوح الآن'), findsOneWidget);
    expect(find.text('مغلق الآن'), findsOneWidget);
    expect(find.textContaining('منتج', findRichText: true), findsNothing);
  });

  testWidgets('العميل يبدّل بين القائمة والشبكة بلا تحميل جديد',
      (tester) async {
    var reads = 0;
    await tester.pumpWidget(MaterialApp(
      home: StoreDirectoryPage(
        loader: () async {
          reads++;
          return _testStores();
        },
        showBanners: false,
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(SliverGrid), findsNothing);
    expect(reads, 1);

    await tester.tap(find.byKey(const Key('directory-layout-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsOneWidget);
    expect(find.text('مفتوح الآن'), findsOneWidget);
    expect(find.text('مغلق الآن'), findsOneWidget);
    expect(reads, 1);

    await tester.tap(find.byKey(const Key('directory-layout-toggle')));
    await tester.pumpAndSettle();
    expect(find.byType(SliverGrid), findsNothing);
    expect(reads, 1);
  });
}
