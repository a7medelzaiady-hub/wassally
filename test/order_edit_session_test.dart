import 'package:city_store/models/order.dart';
import 'package:city_store/models/product.dart';
import 'package:city_store/screens/edit_order_page.dart';
import 'package:city_store/services/order_edit_session.dart';
import 'package:city_store/theme/app_theme.dart';
import 'package:city_store/widgets/qty_stepper.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order() => AppOrder(
      id: 'o1',
      storeId: 'shop1',
      storeName: 'سوبر النور',
      items: const [
        OrderLine('برتقال', 65, 1, 'orange'),
        OrderLine('بصل اخضر', 15.75, 6, 'onion'),
      ],
      subtotal: 159.5,
      deliveryFee: 20,
      total: 179.5,
      status: OrderStatus.newOrder,
      createdAt: DateTime(2026, 11, 27),
      address: 'بيلا حى المحطه شارع 1',
      phone: '01012345678',
      notes: '',
      unavailableItems: const [],
    );

void main() {
  group('OrderEditSession', () {
    test('adding from the store merges by product + options, new items append', () {
      final s = OrderEditSession(_order().items);
      s.add(const Product('برتقال', 65, '', 'orange'));
      expect(s[0].qty, 2);
      expect(s.length, 2);

      const tea = Product('شاي', 20, '', 'tea', true, 0, '', null, '', [], [ProductOption('سكر زيادة', 2)]);
      s.add(tea, qty: 3);
      expect(s.length, 3);
      expect(s[2].productId, 'tea');
      expect(s[2].options, ['سكر زيادة']);
      expect(s[2].optionsTotal, 2);
      expect(s.qtyOf(tea), 3);
      expect(s.qtyOf(const Product('شاي', 18, '', 'tea')), 0, reason: 'من غير خيارات = سطر تاني');

      s.removeOne(tea);
      expect(s.qtyOf(tea), 2);
      expect(s.count, 3);
      s.setQty(0, 0);
      expect(s.count, 2);
      expect(s.subtotal, closeTo(15.75 * 6 + 20 * 2, 0.001));
    });

    test('quantity stays within limits and ignores products without id', () {
      final s = OrderEditSession(_order().items, maxQty: 3);
      s.add(const Product('بصل اخضر', 15.75, '', 'onion'), qty: 10);
      expect(s[1].qty, 3);
      s.add(const Product('صنف يدوي', 5));
      expect(s.length, 2);
      s.setQty(0, 99);
      expect(s[0].qty, 1);
    });
  });

  testWidgets('تعديل الطلب: نفس عداد السلة + زرار حذف + إضافة من المحل', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: EditOrderPage(order: _order()),
      ),
    ));
    await tester.pump();

    // كل صنف ليه عداد (− الكمية +) واحد، مهما كانت الكمية.
    expect(find.byType(QtyStepper), findsNWidgets(2));
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
    expect(find.byKey(const Key('edit-order-add-from-store')), findsOneWidget);
    expect(find.text('أضف أصناف من سوبر النور'), findsOneWidget);

    // الحذف بيشيل الصنف وبيظهر «رجّعه».
    await tester.tap(find.byKey(const ValueKey<String>('edit-line-delete-0')));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('edit-line-restore-0')), findsOneWidget);
    expect(find.byType(QtyStepper), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('edit-line-restore-0')));
    await tester.pump();
    expect(find.byType(QtyStepper), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });
}
