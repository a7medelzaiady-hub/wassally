import 'package:city_store/models/order.dart';
import 'package:city_store/utils/format.dart';
import 'package:city_store/utils/order_receipt.dart';
import 'package:city_store/widgets/order_receipt_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

AppOrder _order({
  OrderStatus status = OrderStatus.delivered,
  double? serviceFee = 5,
  int referralDiscountMinor = 0,
}) =>
    AppOrder(
      id: 'abc12xyz',
      storeName: 'بقالة الحاج سيد',
      items: const [
        OrderLine('سكر', 35, 2),
        OrderLine('شاي', 20, 1, '', ['كيس كبير']),
      ],
      subtotal: 90,
      deliveryFee: 15,
      total: 110,
      status: status,
      createdAt: DateTime(2026, 11, 26, 16, 5),
      deliveredAt: DateTime(2026, 11, 26, 17, 30),
      address: 'عنوان',
      phone: '01000000000',
      notes: '',
      serviceFee: serviceFee,
      referralDiscountMinor: referralDiscountMinor,
    );

void main() {
  test('الإيصال متاح للطلبات المسلّمة بس', () {
    expect(OrderReceipt.available(_order()), isTrue);
    expect(OrderReceipt.available(_order(status: OrderStatus.onTheWay)), isFalse);
    expect(OrderReceipt.available(_order(status: OrderStatus.cancelled)), isFalse);
  });

  test('أرقام الإيصال هي نفس أرقام تفاصيل الطلب', () {
    final r = OrderReceipt.of(_order());
    expect(r.orderNumber, '969626');
    expect(r.orderNumber, simpleOrderNumber('abc12xyz'));
    expect(r.storeName, 'بقالة الحاج سيد');
    expect(r.date, '26/11/2026 - 5:30 م');
    expect(r.items.map((l) => l.label), [
      '2 × سكر',
      '1 × شاي (كيس كبير)',
    ]);
    expect(r.items.first.value, '70 ج.م');
    final totals = {for (final l in r.totals) l.label: l.value};
    expect(totals['المجموع'], '90 ج.م');
    expect(totals['رسوم التوصيل'], '15 ج.م');
    expect(totals['رسوم الخدمة'], '5 ج.م');
    expect(totals['الإجمالي'], '110 ج.م');
    expect(r.totals.last.strong, isTrue);
    expect(r.fileName, 'wasally-receipt-969626.png');
  });

  test('من غير رسوم خدمة ومع خصم الدعوات', () {
    final r = OrderReceipt.of(_order(serviceFee: null, referralDiscountMinor: 500));
    final labels = r.totals.map((l) => l.label).toList();
    expect(labels, isNot(contains('رسوم الخدمة')));
    expect(labels, contains('خصم نقاط الدعوات'));
    expect(
      r.totals.firstWhere((l) => l.label == 'خصم نقاط الدعوات').value,
      '- 5 ج.م',
    );
  });

  testWidgets('شكل الإيصال بيعرض بيانات الطلب وزرار المشاركة', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: OrderReceiptSheet(receipt: OrderReceipt.of(_order())),
      ),
    ));
    expect(find.text('وصّلي'), findsOneWidget);
    expect(find.text('969626'), findsOneWidget);
    expect(find.text('بقالة الحاج سيد'), findsOneWidget);
    expect(find.text('110 ج.م'), findsOneWidget);
    expect(find.byKey(const Key('receipt-share')), findsOneWidget);
    expect(find.byKey(const Key('receipt-save')), findsOneWidget);
    expect(find.text('حفظ في الصور'), findsOneWidget);
    expect(find.byType(RepaintBoundary), findsWidgets);
  });

  test('رقم الطلب البسيط: 6 أرقام وثابت لنفس الطلب', () {
    final a = simpleOrderNumber('abc12xyz');
    expect(a, hasLength(6));
    expect(int.tryParse(a), isNotNull);
    expect(simpleOrderNumber('abc12xyz'), a);
    expect(simpleOrderNumber('other-id'), isNot(a));
  });
}
