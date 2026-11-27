import 'dart:async';

import 'package:city_store/models/store.dart';
import 'package:city_store/screens/store_link_page.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('مسار /s/<id> بس اللي بيفتح صفحة المحل', () {
    expect(StoreLinkPage.routeFor(const RouteSettings(name: '/s/shop1')), isNotNull);
    expect(StoreLinkPage.routeFor(const RouteSettings(name: '/s/bad!id')), isNotNull);
    expect(StoreLinkPage.routeFor(const RouteSettings(name: '/')), isNull);
    expect(StoreLinkPage.routeFor(const RouteSettings(name: '/s')), isNull);
    expect(StoreLinkPage.routeFor(const RouteSettings(name: '/orders')), isNull);
  });

  Widget app(Widget child) => MaterialApp(
        theme: buildAppTheme(),
        home: Directionality(textDirection: TextDirection.rtl, child: child),
      );

  testWidgets('مش مسجل دخول: الرابط بيتحفظ لبعد الدخول', (tester) async {
    StoreLinkPage.pendingStoreId = null;
    await tester.pumpWidget(app(StoreLinkPage(storeId: 'shop1', isSignedIn: () => false)));
    expect(find.byKey(const Key('store-link-sign-in')), findsOneWidget);
    expect(StoreLinkPage.pendingStoreId, 'shop1');
    StoreLinkPage.pendingStoreId = null;
  });

  testWidgets('محل مقفول أو مش موجود: رسالة واضحة', (tester) async {
    await tester.pumpWidget(app(StoreLinkPage(
      storeId: 'gone',
      isSignedIn: () => true,
      loader: (_) async => null,
    )));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('store-link-missing')), findsOneWidget);
  });

  testWidgets('مسجل دخول: بيدوّر على المحل بالرقم وبيعرض تحميل', (tester) async {
    var asked = '';
    final pending = Completer<Store?>();
    await tester.pumpWidget(app(StoreLinkPage(
      storeId: 'shop1',
      isSignedIn: () => true,
      loader: (id) {
        asked = id;
        return pending.future;
      },
    )));
    expect(asked, 'shop1');
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });
}
