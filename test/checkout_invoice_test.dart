import 'package:city_store/widgets/checkout_invoice.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const items = [
    CheckoutInvoiceItem('برنجان رومى', 1, 21),
    CheckoutInvoiceItem('بصل اخضر', 1, 15.8),
    CheckoutInvoiceItem('بصل اصفر', 1, 13.1),
  ];

  testWidgets('فاتورة إتمام الطلب: ثلاثة أعمدة الصنف والكمية والإجمالي', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: CheckoutInvoiceTable(items: items)),
    ));
    expect(find.byKey(const Key('checkout-invoice-header')), findsOneWidget);
    expect(find.text('الصنف'), findsOneWidget);
    expect(find.text('الكمية'), findsOneWidget);
    expect(find.text('الإجمالي'), findsOneWidget);
    expect(find.text('السعر'), findsNothing); // من غير عمود سعر الوحدة
    expect(find.byKey(const Key('checkout-invoice-line-2')), findsOneWidget);
    expect(find.text('برنجان رومى'), findsOneWidget);
    expect(find.text('15.8'), findsOneWidget);
    expect(find.text('21'), findsOneWidget);
  });

  testWidgets('الفاتورة ما تتكسرش على شاشة 320 ومع اسم طويل وكمية كبيرة', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: Padding(
          padding: EdgeInsets.all(16),
          child: Column(children: [
            CheckoutInvoiceTable(items: [
              CheckoutInvoiceItem('فلفل أخضر بلدي طويل الاسم ومعبأ طازج', 12, 1620.5),
            ]),
            CheckoutDashes(),
          ]),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    expect(find.text('12'), findsOneWidget);
  });
}
