import 'package:city_store/models/product.dart';
import 'package:city_store/services/cart_model.dart';
import 'package:city_store/utils/cart_share.dart';
import 'package:city_store/widgets/order_receipt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  CartModel cart0() {
    final c = CartModel();
    c.add(const Product('فالي توك توك', 1300), storeId: 's1', storeName: 'الزيادي لزيوت السيارات');
    c.add(const Product('ليبي 1 لتر', 250), storeId: 's1', storeName: 'الزيادي لزيوت السيارات', qty: 2);
    return c;
  }

  test('إيصال السلة: الأصناف والإجمالي ورابط التطبيق، من غير عنوان أو تليفون', () {
    final r = buildCartReceipt(cart0(), now: DateTime(2026, 11, 27, 1, 0));
    expect(r.title, 'سلتي');
    expect(r.orderNumber, isEmpty);
    expect(r.storeName, 'الزيادي لزيوت السيارات');
    expect(r.items.map((l) => '${l.label}|${l.value}'), [
      '1 × فالي توك توك|1300 ج.م',
      '2 × ليبي 1 لتر|500 ج.م',
    ]);
    expect(r.totals.single.value, '1800 ج.م');
    expect(r.items.map((l) => l.itemName), ['فالي توك توك', 'ليبي 1 لتر']);
    expect(r.items.map((l) => l.quantity), [1, 2]);
    expect(r.items.map((l) => l.unitPrice), [1300, 250]);
    expect(r.qrLink, contains('/s/s1')); // رابط المحل نفسه
    expect(r.shareText, contains('الزيادي لزيوت السيارات'));
    expect(r.fileName, endsWith('.png'));
  });

  testWidgets('شكل الفاتورة الحرارية للسلة', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: OrderReceiptSheet(receipt: buildCartReceipt(cart0()))),
    ));
    expect(find.text('وصّلي'), findsOneWidget);
    expect(find.text('سلتي'), findsOneWidget);
    expect(find.text('1800 ج.م'), findsOneWidget);
    expect(find.byKey(const Key('receipt-table-header')), findsOneWidget);
    expect(find.text('الصنف'), findsOneWidget);
    expect(find.text('الكمية'), findsOneWidget);
    expect(find.text('السعر'), findsOneWidget);
    expect(find.byKey(const Key('receipt-line-1')), findsOneWidget);
    expect(find.text('250'), findsOneWidget);
    expect(find.text('500'), findsOneWidget);
    expect(find.byKey(const Key('receipt-qr')), findsOneWidget);
    expect(find.text('رقم الطلب'), findsNothing);
  });

  testWidgets('أعمدة الإيصال لا تتداخل على شاشة 320 ومع أسماء طويلة', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final c = CartModel();
    c.add(const Product('فلفل أخضر بلدي طويل الاسم ومعبأ طازج', 13.5),
        storeId: 'veg', storeName: 'فواكه وخضروات', qty: 12);
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: OrderReceiptCard(receipt: buildCartReceipt(c)),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('receipt-table-header')), findsOneWidget);
    expect(find.byKey(const Key('receipt-line-0')), findsOneWidget);
    expect(find.text('13.5'), findsOneWidget);
    expect(find.text('162'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
