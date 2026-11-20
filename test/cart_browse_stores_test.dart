import 'package:city_store/screens/cart_page.dart';
import 'package:city_store/screens/store_directory_page.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _PushObserver extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}

void main() {
  testWidgets('السلة الفاضية: "تصفّح المحلات" يفتح قائمة كل المحلات', (tester) async {
    cart.clear();
    final observer = _PushObserver();
    await tester.pumpWidget(MaterialApp(
      navigatorObservers: [observer],
      home: const Scaffold(body: CartPage()),
    ));
    final before = observer.pushed.length;

    await tester.tap(find.text('تصفّح المحلات'));
    // من غير pump: الشاشة الجديدة بتقرا من Firestore، والاختبار بيتأكد من الوجهة بس.
    expect(observer.pushed.length, before + 1);
    final route = observer.pushed.last as MaterialPageRoute<dynamic>;
    final page = route.builder(tester.element(find.byType(CartPage)));
    expect(page, isA<StoreDirectoryPage>());
    expect((page as StoreDirectoryPage).initialCategory, isNull);
  });
}
