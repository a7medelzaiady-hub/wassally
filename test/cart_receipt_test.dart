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
    expect(r.qrLink, contains('com.wassally.app'));
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
    expect(find.byKey(const Key('receipt-qr')), findsOneWidget);
    expect(find.text('رقم الطلب'), findsNothing);
  });
}
